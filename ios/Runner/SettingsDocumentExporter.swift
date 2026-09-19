import Flutter
import UIKit

final class SettingsDocumentExporter: NSObject, UIDocumentPickerDelegate {
  private let fileManager: FileManager
  private var pendingResult: FlutterResult?
  private weak var picker: UIDocumentPickerViewController?

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  func exportDocument(
    sourcePath: String,
    presenter: UIViewController,
    result: @escaping FlutterResult
  ) {
    guard pendingResult == nil else {
      result(
        FlutterError(
          code: "export_in_progress",
          message: "A document export is already in progress.",
          details: nil
        )
      )
      return
    }

    let sourceURL = URL(fileURLWithPath: sourcePath)
    guard fileManager.fileExists(atPath: sourceURL.path) else {
      result(
        FlutterError(
          code: "source_not_found",
          message: "The export file could not be found.",
          details: sourcePath
        )
      )
      return
    }

    let picker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
      picker = UIDocumentPickerViewController(forExporting: [sourceURL], asCopy: true)
    } else {
      picker = UIDocumentPickerViewController(url: sourceURL, in: .exportToService)
    }

    picker.delegate = self
    picker.modalPresentationStyle = .formSheet
    pendingResult = result
    self.picker = picker
    presenter.present(picker, animated: true)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(with: nil)
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    finish(with: urls.first)
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentAt url: URL
  ) {
    finish(with: url)
  }

  private func finish(with url: URL?) {
    let result = pendingResult
    cleanup()
    if let url {
      result?([
        "path": url.path,
      ])
      return
    }
    result?(nil)
  }

  private func cleanup() {
    picker?.delegate = nil
    picker = nil
    pendingResult = nil
  }
}
