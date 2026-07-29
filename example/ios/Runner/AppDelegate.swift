import Flutter
import UIKit
import BackgroundTasks

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  
  private let channelName = "offline_upload_queue/bg_task"
  private var methodChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    methodChannel = FlutterMethodChannel(name: channelName, binaryMessenger: controller.binaryMessenger)
    
    methodChannel?.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      if call.method == "scheduleAppRefresh" {
        guard let args = call.arguments as? [String: Any],
              let identifier = args["identifier"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing identifier", details: nil))
          return
        }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        if let earliestBeginDateSeconds = args["earliestBeginDateSeconds"] as? Int {
          request.earliestBeginDate = Date(timeIntervalSinceNow: TimeInterval(earliestBeginDateSeconds))
        }
        do {
          try BGTaskScheduler.shared.submit(request)
          result(nil)
        } catch {
          result(FlutterError(code: "SUBMIT_FAILED", message: "Failed to submit task: \(error.localizedDescription)", details: nil))
        }
      } else if call.method == "scheduleProcessing" {
        guard let args = call.arguments as? [String: Any],
              let identifier = args["identifier"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing identifier", details: nil))
          return
        }
        let request = BGProcessingTaskRequest(identifier: identifier)
        if let reqNet = args["requiresNetworkConnectivity"] as? Bool {
          request.requiresNetworkConnectivity = reqNet
        }
        if let reqPower = args["requiresExternalPower"] as? Bool {
          request.requiresExternalPower = reqPower
        }
        do {
          try BGTaskScheduler.shared.submit(request)
          result(nil)
        } catch {
          result(FlutterError(code: "SUBMIT_FAILED", message: "Failed to submit task: \(error.localizedDescription)", details: nil))
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    })

    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: "com.example.app.upload_refresh",
      using: nil
    ) { task in
      self.handleAppRefresh(task: task as! BGAppRefreshTask)
    }

    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: "com.example.app.upload_processing",
      using: nil
    ) { task in
      self.handleProcessing(task: task as! BGProcessingTask)
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func handleAppRefresh(task: BGAppRefreshTask) {
    task.expirationHandler = {
      self.methodChannel?.invokeMethod("onExpiration", arguments: nil)
    }
    self.methodChannel?.invokeMethod("onAppRefresh", arguments: nil) { result in
      let hasPending = result as? Bool ?? false
      task.setTaskCompleted(success: true)
      if hasPending {
        let request = BGAppRefreshTaskRequest(identifier: "com.example.app.upload_refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5)
        try? BGTaskScheduler.shared.submit(request)
      }
    }
  }

  func handleProcessing(task: BGProcessingTask) {
    task.expirationHandler = {
      self.methodChannel?.invokeMethod("onExpiration", arguments: nil)
    }
    self.methodChannel?.invokeMethod("onProcessing", arguments: nil) { result in
      let hasPending = result as? Bool ?? false
      task.setTaskCompleted(success: true)
      if hasPending {
        let refreshRequest = BGAppRefreshTaskRequest(identifier: "com.example.app.upload_refresh")
        refreshRequest.earliestBeginDate = Date(timeIntervalSinceNow: 5)
        try? BGTaskScheduler.shared.submit(refreshRequest)
        
        let procRequest = BGProcessingTaskRequest(identifier: "com.example.app.upload_processing")
        procRequest.requiresNetworkConnectivity = true
        try? BGTaskScheduler.shared.submit(procRequest)
      }
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
