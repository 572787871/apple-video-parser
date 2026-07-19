import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var backgroundTasks: [Int: UIBackgroundTaskIdentifier] = [:]
  private var nextBackgroundTaskId: Int = 1

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "web_video_downloader/background_task",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(FlutterError(code: "unavailable", message: "AppDelegate released", details: nil))
          return
        }
        switch call.method {
        case "begin":
          let id = self.nextBackgroundTaskId
          self.nextBackgroundTaskId += 1
          var task: UIBackgroundTaskIdentifier = .invalid
          task = UIApplication.shared.beginBackgroundTask(withName: "VidSnifferDownload") {
            if task != .invalid {
              UIApplication.shared.endBackgroundTask(task)
            }
            self.backgroundTasks.removeValue(forKey: id)
          }
          self.backgroundTasks[id] = task
          result(id)
        case "end":
          if let id = call.arguments as? Int, let task = self.backgroundTasks.removeValue(forKey: id), task != .invalid {
            UIApplication.shared.endBackgroundTask(task)
          }
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
