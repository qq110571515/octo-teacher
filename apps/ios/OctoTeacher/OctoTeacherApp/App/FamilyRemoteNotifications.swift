import Foundation
import OSLog
import UIKit
import UserNotifications

enum FamilyRemotePushLog {
    static let logger = Logger(
        subsystem: "com.octoteacher.app",
        category: "FamilyRemotePush"
    )
}

struct FamilyRemotePushRegistration: Codable, Equatable {
    enum Environment: String, Codable {
        case development
        case production
    }

    var token: String
    var environment: Environment
}
enum FamilyRemoteNotificationStore {
    private static let registrationKey = "octoteacher.family.remotePushRegistration"
    private static let registrationErrorKey = "octoteacher.family.remotePushRegistrationError"

    static var registration: FamilyRemotePushRegistration? {
        get {
            guard let data = UserDefaults.standard.data(forKey: registrationKey) else { return nil }
            return try? JSONDecoder().decode(FamilyRemotePushRegistration.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: registrationKey)
            } else {
                UserDefaults.standard.removeObject(forKey: registrationKey)
            }
        }
    }

    static var lastRegistrationError: String? {
        get { UserDefaults.standard.string(forKey: registrationErrorKey) }
        set { UserDefaults.standard.set(newValue, forKey: registrationErrorKey) }
    }
}

extension Notification.Name {
    static let familyRemotePushRegistrationChanged =
        Notification.Name("octoteacher.family.remotePushRegistrationChanged")
    static let familyScreenTimeRemoteSyncRequested =
        Notification.Name("octoteacher.family.screenTimeRemoteSyncRequested")
}

@MainActor
final class FamilyScreenTimeRemoteSyncRequest: NSObject {
    private var completion: ((UIBackgroundFetchResult) -> Void)?

    init(completion: @escaping (UIBackgroundFetchResult) -> Void) {
        self.completion = completion
    }

    func finish(_ result: UIBackgroundFetchResult) {
        guard let completion else { return }
        self.completion = nil
        completion(result)
    }
}

@MainActor
final class FamilyRemoteNotificationCoordinator {
    static let shared = FamilyRemoteNotificationCoordinator()

    private var pendingScreenTimeRequests: [FamilyScreenTimeRemoteSyncRequest] = []
    private let backgroundSync: @MainActor () async -> UIBackgroundFetchResult
    private let fallbackDelay: Duration

    init(
        fallbackDelay: Duration = .milliseconds(300),
        backgroundSync: @escaping @MainActor () async -> UIBackgroundFetchResult = {
            await FamilyRemoteScreenTimeBackgroundSync.perform()
        }
    ) {
        self.fallbackDelay = fallbackDelay
        self.backgroundSync = backgroundSync
    }

    func enqueue(_ request: FamilyScreenTimeRemoteSyncRequest) {
        pendingScreenTimeRequests.append(request)
        FamilyRemotePushLog.logger.info("Queued Screen Time wake request")
        NotificationCenter.default.post(
            name: .familyScreenTimeRemoteSyncRequested,
            object: request
        )
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: fallbackDelay)
            guard claim(request) else { return }
            let result = await backgroundSync()
            FamilyRemotePushLog.logger.info(
                "Completed headless Screen Time sync with result \(result.rawValue, privacy: .public)"
            )
            request.finish(result)
        }
    }

    func claim(_ request: FamilyScreenTimeRemoteSyncRequest) -> Bool {
        guard let index = pendingScreenTimeRequests.firstIndex(where: { $0 === request }) else {
            return false
        }
        pendingScreenTimeRequests.remove(at: index)
        return true
    }

    func takePendingScreenTimeRequests() -> [FamilyScreenTimeRemoteSyncRequest] {
        let requests = pendingScreenTimeRequests
        pendingScreenTimeRequests.removeAll()
        return requests
    }
}

@MainActor
private enum FamilyRemoteScreenTimeBackgroundSync {
    static func perform() async -> UIBackgroundFetchResult {
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        let secrets = KeychainFamilyCloudSecretStore()
        guard let token = secrets.load(account: "child_device_session") else {
            FamilyRemotePushLog.logger.notice(
                "Headless Screen Time sync skipped because child session is unavailable"
            )
            return .noData
        }

        do {
            let client = FamilyCloudClient()
            let profile = try await client.loadChildProfile(token: token)
            let manager = ScreenTimePOCManager()
            let controller = MockScreenTimeController(
                persistenceKey: "octoteacher.screentime.session"
            )
            if manager.resetStaleDeviceEnforcementIfNeeded() {
                controller.resetPersistedSessionWithoutRelock()
            }
            manager.migrateLegacyIndividualAuthorizationIfNeeded(isChildDevice: true)
            let status = manager.applySyncedPolicy(profile.screenTimePolicy)
            if status.enforcement == .applied,
               let control = profile.screenTimePolicy?.control,
               status.appliedControlCommandId == control.commandId {
                _ = controller.reconcileGuardianControl(control)
            }
            _ = try await client.updateChildScreenTimeStatus(
                token: token,
                status: status
            )
            FamilyRemotePushLog.logger.info(
                "Headless Screen Time policy reconciliation completed"
            )
            return .newData
        } catch {
            FamilyRemotePushLog.logger.error(
                "Headless Screen Time policy reconciliation failed"
            )
            return .failed
        }
        #else
        return .noData
        #endif
    }
}

@MainActor
final class OctoTeacherAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        #if DEBUG
        let environment = FamilyRemotePushRegistration.Environment.development
        #else
        let environment = FamilyRemotePushRegistration.Environment.production
        #endif
        FamilyRemoteNotificationStore.registration = .init(
            token: token,
            environment: environment
        )
        FamilyRemoteNotificationStore.lastRegistrationError = nil
        FamilyRemotePushLog.logger.info(
            "Registered APNs device token for \(environment.rawValue, privacy: .public)"
        )
        NotificationCenter.default.post(
            name: .familyRemotePushRegistrationChanged,
            object: nil
        )
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        let failure = error as NSError
        FamilyRemoteNotificationStore.lastRegistrationError =
            "\(failure.domain):\(failure.code)"
        FamilyRemotePushLog.logger.error(
            "APNs registration failed: \(failure.domain, privacy: .public) \(failure.code, privacy: .public)"
        )
        NotificationCenter.default.post(
            name: .familyRemotePushRegistrationChanged,
            object: nil
        )
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard let payload = userInfo["octoteacher"] as? [String: Any],
              payload["kind"] as? String == "screen_time_sync" else {
            completionHandler(.noData)
            return
        }
        FamilyRemotePushLog.logger.info("Received Screen Time wake push")
        let request = FamilyScreenTimeRemoteSyncRequest(completion: completionHandler)
        FamilyRemoteNotificationCoordinator.shared.enqueue(request)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(25))
            request.finish(.failed)
        }
    }
}
