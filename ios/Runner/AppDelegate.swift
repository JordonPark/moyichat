import Flutter
import UIKit
import Vision
import os

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let device = FlutterMethodChannel(
      name: "moyichat/device",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    device.setMethodCallHandler { call, result in
      guard call.method == "memory" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result([
        "total": Int64(ProcessInfo.processInfo.physicalMemory),
        "available": Int64(os_proc_available_memory()),
      ])
    }
    let channel = FlutterMethodChannel(
      name: "moyichat/photos",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard let path = call.arguments as? String else {
        result(FlutterError(code: "invalid_path", message: "A path is required.", details: nil))
        return
      }
      switch call.method {
      case "excludeFromBackup":
        do {
          var url = URL(fileURLWithPath: path, isDirectory: true)
          var values = URLResourceValues()
          values.isExcludedFromBackup = true
          try url.setResourceValues(values)
          result(nil)
        } catch {
          result(FlutterError(code: "backup_setting", message: "Could not set backup exclusion.", details: nil))
        }
      case "analyze":
        DispatchQueue.global(qos: .userInitiated).async {
          let findings = Self.analyzePhoto(at: URL(fileURLWithPath: path))
          DispatchQueue.main.async { result(findings) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func analyzePhoto(at url: URL) -> Any {
    let source = VNImageRequestHandler(url: url, options: [:])
    let text = VNRecognizeTextRequest()
    text.revision = VNRecognizeTextRequestRevision3
    text.recognitionLevel = .accurate
    text.recognitionLanguages = ["ko-KR", "en-US"]
    text.usesLanguageCorrection = true
    let classification = VNClassifyImageRequest()

    var findings: [String: Any] = [:]
    if (try? source.perform([text])) != nil {
      let lines = text.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
      findings["text"] = lines.joined(separator: "\n")
    }
    if (try? source.perform([classification])) != nil {
      let candidates = (classification.results ?? [])
        .filter { $0.confidence >= 0.35 }
        .sorted { $0.confidence > $1.confidence }
        .prefix(5)
      findings["labels"] = candidates.map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
    }
    if findings.isEmpty {
      return FlutterError(code: "analysis_failed", message: "Image analysis failed.", details: nil)
    }
    return findings
  }
}
