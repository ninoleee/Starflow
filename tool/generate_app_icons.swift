import Foundation

// Keep the historical entry point on the same source and export pipeline.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = [
  ProcessInfo.processInfo.environment["PYTHON"] ?? "python3",
  root.appendingPathComponent("tool/generate_brand_assets.py").path,
]
process.currentDirectoryURL = root
try process.run()
process.waitUntilExit()
exit(process.terminationStatus)
