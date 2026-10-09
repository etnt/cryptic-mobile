import Flutter
import UIKit

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
    let channel = FlutterMethodChannel(
      name: "cryptic/media_storage",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "securePath",
            let arguments = call.arguments as? [String: Any],
            let path = arguments["path"] as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let supportDirectory = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first else {
        result(FlutterError(
          code: "MEDIA_STORAGE_PATH",
          message: "Application Support directory is unavailable",
          details: nil
        ))
        return
      }
      let mediaPath = supportDirectory
        .appendingPathComponent("media", isDirectory: true)
        .standardizedFileURL
        .resolvingSymlinksInPath()
        .path
      let requestedPath = URL(fileURLWithPath: path)
        .standardizedFileURL
        .resolvingSymlinksInPath()
        .path
      guard requestedPath == mediaPath ||
        requestedPath.hasPrefix(mediaPath + "/")
      else {
        result(FlutterError(
          code: "MEDIA_STORAGE_PATH",
          message: "Only paths in the app media directory can be secured",
          details: nil
        ))
        return
      }
      do {
        // Complete protection is intentional: media cannot be saved while the
        // device is locked, including attachments received in the background.
        try FileManager.default.setAttributes(
          [.protectionKey: FileProtectionType.complete],
          ofItemAtPath: requestedPath
        )
        var url = URL(fileURLWithPath: requestedPath)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        result(nil)
      } catch {
        result(FlutterError(
          code: "MEDIA_STORAGE_SECURITY",
          message: error.localizedDescription,
          details: nil
        ))
      }
    }
  }
}
