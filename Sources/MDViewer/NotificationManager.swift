import Foundation
import UserNotifications

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    private var didRequest = false
    private var authorized = false

    private lazy var timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    func requestAuthIfNeeded() {
        guard !didRequest else { return }
        didRequest = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in self.authorized = granted }
        }
        // 이미 부여된 권한 확인
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                    self.authorized = true
                }
            }
        }
    }

    func notifyFileUpdated(url: URL, addedCount: Int, removedCount: Int, time: Date = Date()) {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = url.lastPathComponent
        let summary: String
        if addedCount > 0 || removedCount > 0 {
            summary = "+\(addedCount) / −\(removedCount) · \(timeFormatter.string(from: time))"
        } else {
            summary = "업데이트됨 · \(timeFormatter.string(from: time))"
        }
        content.body = summary
        content.sound = .default
        // 같은 파일은 알림 묶이도록 threadIdentifier 사용
        content.threadIdentifier = url.path
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}
