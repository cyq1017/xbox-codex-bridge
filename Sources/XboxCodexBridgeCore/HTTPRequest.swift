import Foundation

public struct HTTPRequest: Equatable, Sendable {
  public let method: String
  public let path: String
  public let headers: [String: String]
  public let body: Data
}

public enum HTTPRequestError: LocalizedError, Equatable {
  case headersTooLarge
  case bodyTooLarge
  case malformed

  public var errorDescription: String? {
    switch self {
    case .headersTooLarge:
      return "HTTP headers exceed the supported size"
    case .bodyTooLarge:
      return "HTTP body exceeds the supported size"
    case .malformed:
      return "Malformed HTTP request"
    }
  }
}

public enum HTTPRequestParser {
  public static let maximumHeaderBytes = 16 * 1024
  public static let maximumBodyBytes = 1024 * 1024
  private static let separator = Data("\r\n\r\n".utf8)

  public static func parse(_ data: Data) throws -> HTTPRequest? {
    guard let separatorRange = data.range(of: separator) else {
      if data.count > maximumHeaderBytes {
        throw HTTPRequestError.headersTooLarge
      }
      return nil
    }
    guard separatorRange.lowerBound <= maximumHeaderBytes else {
      throw HTTPRequestError.headersTooLarge
    }
    guard let headerText = String(data: data[..<separatorRange.lowerBound], encoding: .utf8) else {
      throw HTTPRequestError.malformed
    }

    let lines = headerText.components(separatedBy: "\r\n")
    guard let requestLine = lines.first else {
      throw HTTPRequestError.malformed
    }
    let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
    guard requestParts.count == 3, requestParts[2].hasPrefix("HTTP/1.") else {
      throw HTTPRequestError.malformed
    }

    var headers: [String: String] = [:]
    for line in lines.dropFirst() where !line.isEmpty {
      guard let colon = line.firstIndex(of: ":") else {
        throw HTTPRequestError.malformed
      }
      let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
      let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
      guard !name.isEmpty, headers[name] == nil else {
        throw HTTPRequestError.malformed
      }
      headers[name] = value
    }

    let contentLength: Int
    if let rawLength = headers["content-length"] {
      guard let parsedLength = Int(rawLength), parsedLength >= 0 else {
        throw HTTPRequestError.malformed
      }
      contentLength = parsedLength
    } else {
      contentLength = 0
    }
    guard contentLength <= maximumBodyBytes else {
      throw HTTPRequestError.bodyTooLarge
    }

    let bodyStart = separatorRange.upperBound
    guard data.count >= bodyStart + contentLength else {
      return nil
    }
    let body = data[bodyStart..<(bodyStart + contentLength)]
    let target = String(requestParts[1])
    let path = target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? target

    return HTTPRequest(
      method: String(requestParts[0]).uppercased(),
      path: path,
      headers: headers,
      body: Data(body)
    )
  }
}
