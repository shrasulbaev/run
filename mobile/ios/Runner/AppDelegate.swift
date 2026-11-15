import Flutter
import UIKit
import CoreMotion

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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AdamSteps") {
      AdamSteps.register(with: registrar)
    }
  }
}

// Core Motion owns detection and historical storage; never infer steps from GPS.
final class AdamSteps: NSObject, FlutterPlugin {
  private let pedometer = CMPedometer()
  private var historyDay = ""
  private var historyCache: [String: Int] = [:]
  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = AdamSteps()
    registrar.addMethodCallDelegate(instance, channel: FlutterMethodChannel(name: "kg.adamrun/steps", binaryMessenger: registrar.messenger()))
  }
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "snapshot" else { result(FlutterMethodNotImplemented); return }
    guard CMPedometer.isStepCountingAvailable() else {
      result(["status": "unsupported", "source": "Core Motion"]); return
    }
    let request = (call.arguments as? [String: Any])?["request"] as? Bool ?? false
    let status = CMPedometer.authorizationStatus()
    if status == .denied || status == .restricted {
      result(["status": "denied", "source": "Core Motion"]); return
    }
    if status == .notDetermined && !request {
      result(["status": "permissionRequired", "source": "Core Motion"]); return
    }
    let calendar = Calendar.current
    let stamp = Date()
    let start = calendar.startOfDay(for: stamp)
    let cachedDay = historyDay
    let cachedHistory = historyCache
    pedometer.queryPedometerData(from: start, to: stamp) { [weak self] data, error in
      guard let self else { return }
      guard let data else {
        DispatchQueue.main.async { result(["status": CMPedometer.authorizationStatus() == .denied ? "denied" : "error", "source": "Core Motion"]) }
        return
      }
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.calendar = Calendar(identifier: .gregorian)
      formatter.timeZone = calendar.timeZone
      formatter.dateFormat = "yyyy-MM-dd"
      let key = formatter.string(from: start)
      let count = data.numberOfSteps.intValue
      if cachedDay == key {
        var history = cachedHistory
        history[key] = count
        DispatchQueue.main.async { result(["status": "ready", "source": "Core Motion · iPhone", "count": count, "day": key, "history": history, "partial": false]) }
        return
      }
      let group = DispatchGroup()
      let lock = NSLock()
      var history = [key: count]
      for offset in 1...6 {
        guard let from = calendar.date(byAdding: .day, value: -offset, to: start),
              let to = calendar.date(byAdding: .day, value: 1, to: from) else { continue }
        let day = formatter.string(from: from)
        group.enter()
        self.pedometer.queryPedometerData(from: from, to: to) { old, _ in
          if let old { lock.lock(); history[day] = old.numberOfSteps.intValue; lock.unlock() }
          group.leave()
        }
      }
      group.notify(queue: .main) {
        self.historyDay = key; self.historyCache = history
        result(["status": "ready", "source": "Core Motion · iPhone", "count": count, "day": key, "history": history, "partial": false])
      }
    }
  }
}
