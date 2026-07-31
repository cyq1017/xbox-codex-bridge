import AppKit
import Foundation

let arguments = CommandLine.arguments
let shouldOpenBrowser = !arguments.contains("--no-open")
let shouldPromptForPermission = !arguments.contains("--no-permission-prompt")
let isEphemeral = arguments.contains("--ephemeral")
let shouldRequestAccessibility = arguments.contains("--request-accessibility")
let shouldReportAccessibility = arguments.contains("--ax-status")
let shouldPrintDictationDiagnostics = arguments.contains("--dictation-diagnostics")

func argumentValue(after flag: String) -> String? {
  guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
    return nil
  }
  return arguments[index + 1]
}

let requestedPort = argumentValue(after: "--port").flatMap(UInt16.init) ?? 8765
let configURL: URL
if isEphemeral {
  configURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("XboxCodexBridge-SmokeTest")
    .appendingPathComponent("mapping.json")
} else {
  let applicationSupport = FileManager.default.urls(
    for: .applicationSupportDirectory,
    in: .userDomainMask
  ).first!
  configURL =
    applicationSupport
    .appendingPathComponent("XboxCodexBridge")
    .appendingPathComponent("mapping.json")
}

let dispatcher = CommandDispatcher()
if shouldRequestAccessibility {
  dispatcher.requestAccessibilityIfNeeded()
  print("ACCESSIBILITY \(dispatcher.isAccessibilityTrusted)")
  fflush(stdout)
  exit(dispatcher.isAccessibilityTrusted ? EXIT_SUCCESS : EXIT_FAILURE)
}

if shouldReportAccessibility {
  print("ACCESSIBILITY \(dispatcher.isAccessibilityTrusted)")
  fflush(stdout)
  exit(EXIT_SUCCESS)
}

let dictationController = CodexDictationController(client: SystemCodexAccessibilityClient())
if shouldPrintDictationDiagnostics {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  guard let data = try? encoder.encode(dictationController.diagnostics()) else {
    fputs("Unable to encode dictation diagnostics\n", stderr)
    exit(EXIT_FAILURE)
  }
  print(String(decoding: data, as: UTF8.self))
  fflush(stdout)
  exit(EXIT_SUCCESS)
}

let controllerService = ControllerService()
let runtime = BridgeRuntime(
  dispatcher: dispatcher,
  dictationController: dictationController,
  controllerService: controllerService,
  configURL: configURL
)
let server = LocalHTTPServer(runtime: runtime)

if shouldPromptForPermission {
  dispatcher.requestAccessibilityIfNeeded()
}
runtime.start()

do {
  try server.start(port: requestedPort) { url in
    print("READY \(url.absoluteString)")
    fflush(stdout)
    if shouldOpenBrowser {
      NSWorkspace.shared.open(url)
    }
  }
} catch {
  fputs("Unable to start Xbox Codex Bridge: \(error.localizedDescription)\n", stderr)
  exit(EXIT_FAILURE)
}

RunLoop.main.run()
