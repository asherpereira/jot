import Flutter
import UIKit
import WatchConnectivity

@main
@objc class AppDelegate: FlutterAppDelegate, WCSessionDelegate {
  private var watchChannel: FlutterMethodChannel?
  private let inboxKey = "jot.watch.inbox"
  private let snapshotKey = "jot.watch.snapshot"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = registrar(forPlugin: "JotWatchBridge") {
      let channel = FlutterMethodChannel(name: "jot/watch", binaryMessenger: registrar.messenger())
      watchChannel = channel
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self else { result(nil); return }
        var inbox = UserDefaults.standard.dictionary(forKey: self.inboxKey) as? [String: String] ?? [:]
        switch call.method {
        case "pending": result(Array(inbox.values))
        case "ack":
          if let id = call.arguments as? String {
            inbox.removeValue(forKey: id)
            UserDefaults.standard.set(inbox, forKey: self.inboxKey)
          }
          result(nil)
        case "publish":
          if let snapshot = call.arguments as? String {
            UserDefaults.standard.set(snapshot, forKey: self.snapshotKey)
            self.publish()
          }
          result(nil)
        default: result(FlutterMethodNotImplemented)
        }
      }
    }
    if WCSession.isSupported() {
      WCSession.default.delegate = self
      WCSession.default.activate()
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func publish() {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
          let json = UserDefaults.standard.string(forKey: snapshotKey) else { return }
    try? session.updateApplicationContext(["snapshot": json])
  }

  func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
    guard let id = userInfo["id"] as? String, let json = userInfo["action"] as? String else { return }
    DispatchQueue.main.async {
      var inbox = UserDefaults.standard.dictionary(forKey: self.inboxKey) as? [String: String] ?? [:]
      inbox[id] = json
      UserDefaults.standard.set(inbox, forKey: self.inboxKey)
      self.watchChannel?.invokeMethod("changed", arguments: nil)
    }
  }

  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    DispatchQueue.main.async { self.publish() }
  }
  func sessionWatchStateDidChange(_ session: WCSession) { DispatchQueue.main.async { self.publish() } }
  func sessionDidBecomeInactive(_ session: WCSession) {}
  func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
