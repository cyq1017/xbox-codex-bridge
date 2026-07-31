import Foundation
import Network
import XboxCodexBridgeCore

final class LocalHTTPServer {
  private let runtime: BridgeRuntime
  private let queue = DispatchQueue(label: "XboxCodexBridge.LocalHTTPServer")
  private let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
  private var listener: NWListener?
  private var origin: String?

  init(runtime: BridgeRuntime) {
    self.runtime = runtime
  }

  func start(port: UInt16 = 8765, onReady: @escaping (URL) -> Void) throws {
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(
      host: "127.0.0.1",
      port: NWEndpoint.Port(rawValue: port) ?? .any
    )
    let listener = try NWListener(using: parameters)
    self.listener = listener
    listener.newConnectionHandler = { [weak self] connection in
      self?.handle(connection)
    }
    listener.stateUpdateHandler = { [weak self, weak listener] state in
      guard let self, let listener else { return }
      switch state {
      case .ready:
        guard let port = listener.port,
          let url = URL(string: "http://127.0.0.1:\(port.rawValue)/")
        else { return }
        self.origin = "http://127.0.0.1:\(port.rawValue)"
        DispatchQueue.main.async { onReady(url) }
      case .failed(let error):
        fputs("Local server failed: \(error)\n", stderr)
      default:
        break
      }
    }
    listener.start(queue: queue)
  }

  func stop() {
    listener?.cancel()
    listener = nil
  }

  private func handle(_ connection: NWConnection) {
    connection.start(queue: queue)
    receive(on: connection, accumulated: Data())
  }

  private func receive(on connection: NWConnection, accumulated: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
      [weak self] data, _, isComplete, error in
      guard let self else { return }
      var buffer = accumulated
      if let data { buffer.append(data) }

      do {
        if let request = try HTTPRequestParser.parse(buffer) {
          self.send(self.route(request), on: connection)
          return
        }
      } catch {
        self.send(.text(400, error.localizedDescription), on: connection)
        return
      }

      if isComplete || error != nil {
        connection.cancel()
        return
      }
      self.receive(on: connection, accumulated: buffer)
    }
  }

  private func route(_ request: HTTPRequest) -> HTTPResponse {
    if let event = HookHapticRequestMatcher.event(for: request) {
      runtime.handleHookHaptic(event)
      return .jsonMessage(202, "Hook accepted")
    }

    switch (request.method, request.path) {
    case ("GET", "/"):
      var response = staticResource("index", extension: "html", mime: "text/html; charset=utf-8")
      response.headers["Set-Cookie"] = "bridge_token=\(token); HttpOnly; SameSite=Strict; Path=/"
      response.headers["Content-Security-Policy"] =
        "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:"
      return response
    case ("GET", "/app.js"):
      return staticResource("app", extension: "js", mime: "text/javascript; charset=utf-8")
    case ("GET", "/styles.css"):
      return staticResource("styles", extension: "css", mime: "text/css; charset=utf-8")
    case ("GET", "/api/state"):
      var response = json(runtime.currentSnapshot())
      if !hasValidCookie(request) {
        response.headers["Set-Cookie"] = "bridge_token=\(token); HttpOnly; SameSite=Strict; Path=/"
      }
      return response
    case ("GET", "/api/config"):
      return json(runtime.currentConfiguration())
    case ("GET", "/api/actions"):
      return json(ActionCatalog.all)
    case ("GET", "/api/windows"):
      guard hasValidCookie(request) else { return .text(403, "Forbidden") }
      return json(runtime.codexWindows())
    case ("GET", "/api/diagnostics/dictation"):
      guard hasValidCookie(request) else { return .text(403, "Forbidden") }
      return json(runtime.dictationDiagnostics())
    case ("GET", "/api/diagnostics/model-picker"):
      guard hasValidCookie(request) else { return .text(403, "Forbidden") }
      return json(runtime.modelPickerCandidates())
    case ("GET", "/api/diagnostics/model-menu-items"):
      guard hasValidCookie(request) else { return .text(403, "Forbidden") }
      return json(runtime.visibleModelMenuItems())
    case ("GET", "/api/diagnostics/model-overlay-elements"):
      guard hasValidCookie(request) else { return .text(403, "Forbidden") }
      return json(runtime.visibleModelOverlayElements())
    default:
      guard request.method == "POST" else {
        return .text(404, "Not found")
      }
      guard isAuthorized(request) else {
        return .text(403, "Forbidden")
      }
      return routeMutation(request)
    }
  }

  private func routeMutation(_ request: HTTPRequest) -> HTTPResponse {
    do {
      switch request.path {
      case "/api/config":
        let configuration = try JSONDecoder().decode(
          MappingConfiguration.self,
          from: request.body
        )
        try runtime.updateConfiguration(configuration)
        return .jsonMessage(200, "Mapping saved")
      case "/api/action":
        let payload = try JSONDecoder().decode(ActionRequest.self, from: request.body)
        try runtime.testAction(payload.id)
        return .jsonMessage(202, "Action queued")
      case "/api/window":
        let payload = try JSONDecoder().decode(WindowRequest.self, from: request.body)
        try runtime.focusCodexWindow(id: payload.id)
        return .jsonMessage(200, "Codex window focused")
      case "/api/haptic":
        return runtime.testHaptic()
          ? .jsonMessage(200, "Haptic played")
          : .jsonMessage(409, "Haptics unavailable")
      case "/api/light":
        let payload = try JSONDecoder().decode(LightRequest.self, from: request.body)
        guard payload.isValid else {
          return .jsonMessage(422, "RGB values must be between 0 and 1")
        }
        return runtime.testLight(red: payload.red, green: payload.green, blue: payload.blue)
          ? .jsonMessage(200, "Light command sent")
          : .jsonMessage(409, "Controller light unavailable")
      default:
        return .text(404, "Not found")
      }
    } catch {
      return .jsonMessage(422, error.localizedDescription)
    }
  }

  private func isAuthorized(_ request: HTTPRequest) -> Bool {
    guard request.headers["origin"] == origin,
      request.headers["content-type"]?.lowercased().hasPrefix("application/json") == true,
      hasValidCookie(request)
    else {
      return false
    }
    return true
  }

  private func hasValidCookie(_ request: HTTPRequest) -> Bool {
    guard let cookie = request.headers["cookie"] else { return false }
    return cookie.split(separator: ";").contains { part in
      part.trimmingCharacters(in: .whitespaces) == "bridge_token=\(token)"
    }
  }

  private func staticResource(_ name: String, extension fileExtension: String, mime: String)
    -> HTTPResponse
  {
    let appResourceURL = Bundle.main.resourceURL?
      .appendingPathComponent("Web")
      .appendingPathComponent("\(name).\(fileExtension)")
    let moduleResourceURL = Bundle.module.url(
      forResource: name,
      withExtension: fileExtension,
      subdirectory: "Web"
    )

    guard
      let url = [appResourceURL, moduleResourceURL].compactMap({ $0 }).first(where: {
        FileManager.default.fileExists(atPath: $0.path)
      }), let data = try? Data(contentsOf: url)
    else {
      return .text(404, "Resource not found")
    }
    return HTTPResponse(status: 200, mime: mime, body: data)
  }

  private func json<T: Encodable>(_ value: T) -> HTTPResponse {
    guard let data = try? JSONEncoder().encode(value) else {
      return .text(500, "Encoding failed")
    }
    return HTTPResponse(status: 200, mime: "application/json; charset=utf-8", body: data)
  }

  private func send(_ response: HTTPResponse, on connection: NWConnection) {
    connection.send(
      content: response.serialized(),
      completion: .contentProcessed { _ in
        connection.cancel()
      })
  }
}

private struct ActionRequest: Decodable {
  let id: String
}

private struct WindowRequest: Decodable {
  let id: String
}

private struct LightRequest: Decodable {
  let red: Float
  let green: Float
  let blue: Float

  var isValid: Bool {
    [red, green, blue].allSatisfy { $0.isFinite && (0...1).contains($0) }
  }
}

private struct HTTPResponse {
  let status: Int
  let mime: String
  let body: Data
  var headers: [String: String] = [:]

  static func text(_ status: Int, _ value: String) -> HTTPResponse {
    HTTPResponse(
      status: status,
      mime: "text/plain; charset=utf-8",
      body: Data(value.utf8)
    )
  }

  static func jsonMessage(_ status: Int, _ message: String) -> HTTPResponse {
    let data =
      (try? JSONEncoder().encode(MessageBody(message: message)))
      ?? Data("{\"message\":\"Unable to encode response\"}".utf8)
    return HTTPResponse(
      status: status,
      mime: "application/json; charset=utf-8",
      body: data
    )
  }

  func serialized() -> Data {
    let reason: String
    switch status {
    case 200: reason = "OK"
    case 202: reason = "Accepted"
    case 400: reason = "Bad Request"
    case 403: reason = "Forbidden"
    case 404: reason = "Not Found"
    case 409: reason = "Conflict"
    case 422: reason = "Unprocessable Content"
    default: reason = "Internal Server Error"
    }
    var allHeaders = headers
    allHeaders["Content-Type"] = mime
    allHeaders["Content-Length"] = String(body.count)
    allHeaders["Cache-Control"] = "no-store"
    allHeaders["Connection"] = "close"
    allHeaders["X-Content-Type-Options"] = "nosniff"
    let headerLines =
      allHeaders
      .sorted { $0.key < $1.key }
      .map { "\($0.key): \($0.value)" }
      .joined(separator: "\r\n")
    var data = Data("HTTP/1.1 \(status) \(reason)\r\n\(headerLines)\r\n\r\n".utf8)
    data.append(body)
    return data
  }
}

private struct MessageBody: Encodable {
  let message: String
}
