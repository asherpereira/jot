import SwiftUI
import WatchConnectivity

struct GlanceTask: Identifiable, Codable {
  let id: Int
  let title: String
  let meta: String
}

final class WatchInbox: NSObject, ObservableObject, WCSessionDelegate {
  @Published private(set) var tasks: [GlanceTask] = []
  @Published var feedback = ""
  private let snapshotKey = "jot.tasks"
  private let outboxKey = "jot.actions"

  override init() {
    super.init()
    if let data = UserDefaults.standard.data(forKey: snapshotKey),
       let saved = try? JSONDecoder().decode([GlanceTask].self, from: data) { tasks = saved }
    if WCSession.isSupported() {
      WCSession.default.delegate = self
      WCSession.default.activate()
    }
  }

  func send(_ fields: [String: Any]) {
    let id = UUID().uuidString
    var action = fields
    action["id"] = id
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd"
    action["localDate"] = formatter.string(from: Date())
    guard let data = try? JSONSerialization.data(withJSONObject: action),
          let json = String(data: data, encoding: .utf8) else { return }
    var queue = UserDefaults.standard.dictionary(forKey: outboxKey) as? [String: String] ?? [:]
    queue[id] = json
    UserDefaults.standard.set(queue, forKey: outboxKey)
    feedback = "Queued for iPhone"
    flush()
  }

  private func flush() {
    guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
    let queue = UserDefaults.standard.dictionary(forKey: outboxKey) as? [String: String] ?? [:]
    let inFlight = Set(WCSession.default.outstandingUserInfoTransfers.compactMap { $0.userInfo["id"] as? String })
    for (id, json) in queue where !inFlight.contains(id) {
      WCSession.default.transferUserInfo(["id": id, "action": json])
    }
  }

  func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
    guard error == nil, let id = userInfoTransfer.userInfo["id"] as? String else { return }
    DispatchQueue.main.async {
      var queue = UserDefaults.standard.dictionary(forKey: self.outboxKey) as? [String: String] ?? [:]
      queue.removeValue(forKey: id)
      UserDefaults.standard.set(queue, forKey: self.outboxKey)
    }
  }
  private func receive(_ context: [String: Any]) {
    guard let json = context["snapshot"] as? String, let data = json.data(using: .utf8),
          let snapshot = try? JSONDecoder().decode([GlanceTask].self, from: data) else { return }
    DispatchQueue.main.async {
      self.tasks = snapshot
      UserDefaults.standard.set(data, forKey: self.snapshotKey)
    }
  }
  func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    receive(applicationContext)
  }
  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    receive(session.receivedApplicationContext)
    DispatchQueue.main.async { self.flush() }
  }
  func retry() { flush() }
}

@main
struct JotWatchApp: App {
  @StateObject private var inbox = WatchInbox()
  @State private var capture = ""
  @Environment(\.scenePhase) private var phase
  var body: some Scene {
    WindowGroup {
      NavigationStack {
        List {
          Section("Up next") {
            if inbox.tasks.isEmpty { Text("No homework from iPhone yet.").foregroundStyle(.secondary) }
            ForEach(inbox.tasks) { task in
              VStack(alignment: .leading) {
                Text(task.title).font(.headline)
                Text(task.meta).font(.caption2).foregroundStyle(.secondary)
                Button("Mark done") { inbox.send(["kind": "complete", "taskId": task.id]) }
              }
            }
          }
          Section("Capture") {
            TextField("Homework", text: $capture)
            Button("Save to iPhone") {
              let trimmed = capture.trimmingCharacters(in: .whitespacesAndNewlines)
              let text = String(trimmed.unicodeScalars.prefix(2000))
              inbox.send(["kind": "capture", "text": text])
              capture = ""
            }.disabled(capture.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if !inbox.feedback.isEmpty { Text(inbox.feedback).font(.caption2) }
          }
        }.navigationTitle("Jot")
      }.onChange(of: phase) { _, newPhase in if newPhase == .active { inbox.retry() } }
    }
  }
}
