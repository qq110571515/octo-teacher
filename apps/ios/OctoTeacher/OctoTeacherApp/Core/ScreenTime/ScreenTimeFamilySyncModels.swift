import Foundation
import CryptoKit

enum FamilyScreenTimeControlMode: String, Codable, Equatable {
    case locked
    case unlocked
}

enum FamilyScreenTimeControlDecision: Equatable {
    case noCommand
    case lock
    case keepUnlock(until: Date)
    case startUnlock(until: Date)
    case reject(errorCode: String)
}

struct FamilyScreenTimeControlReceipt: Equatable {
    var mode: FamilyScreenTimeControlMode
    var unlockUntil: String?
}

struct FamilyScreenTimeControl: Codable, Equatable {
    var schemaVersion: Int
    var commandId: String
    var mode: FamilyScreenTimeControlMode
    var issuedAt: String
    var unlockUntil: String?

    var unlockEndDate: Date? {
        guard let unlockUntil else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: unlockUntil) ?? ISO8601DateFormatter().date(from: unlockUntil)
    }

    var accountingSessionID: UUID {
        let digest = SHA256.hash(data: Data(commandId.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let characters = Array(digest)
        let first = String(characters[0..<8])
        let second = String(characters[8..<12])
        let third = String(characters[12..<16])
        let fourth = String(characters[16..<20])
        let fifth = String(characters[20..<32])
        let uuidText = "\(first)-\(second)-\(third)-\(fourth)-\(fifth)"
        return UUID(uuidString: uuidText)!
    }

    func effectiveReceipt(referenceDate: Date) -> FamilyScreenTimeControlReceipt {
        guard mode == .unlocked,
              let endDate = unlockEndDate,
              endDate > referenceDate else {
            return FamilyScreenTimeControlReceipt(mode: .locked, unlockUntil: nil)
        }
        return FamilyScreenTimeControlReceipt(mode: .unlocked, unlockUntil: unlockUntil)
    }

    func decision(
        activeUnlockEnd: Date?,
        referenceDate: Date,
        minimumStartDuration: TimeInterval
    ) -> FamilyScreenTimeControlDecision {
        guard schemaVersion == 1, !commandId.isEmpty else {
            return .reject(errorCode: "invalid_control_command")
        }
        guard mode == .unlocked else { return .lock }
        guard let endDate = unlockEndDate else {
            return .reject(errorCode: "invalid_control_expiry")
        }
        if endDate <= referenceDate { return .lock }
        if activeUnlockEnd == endDate { return .keepUnlock(until: endDate) }
        guard endDate.timeIntervalSince(referenceDate) >= minimumStartDuration else {
            return .reject(errorCode: "remote_unlock_too_close_to_expiry")
        }
        return .startUnlock(until: endDate)
    }
}

/// A guardian-authored Screen Time policy. The child device only applies this opaque selection
/// and acknowledges the exact revision, hash, and command that reached ManagedSettings.
struct FamilyScreenTimePolicy: Codable, Equatable {
    /// Version 3 restores guardian-authored cross-device policies and binds every policy to
    /// the exact opaque selection payload acknowledged by the child device.
    static let currentSchemaVersion = 3

    var schemaVersion: Int = currentSchemaVersion
    var revision: Int
    var selectionData: String
    var selectionHash: String? = nil
    var applicationCount: Int
    var categoryCount: Int
    var webDomainCount: Int
    var catalogBinding: FamilyScreenTimeCatalogBinding? = nil
    var control: FamilyScreenTimeControl? = nil
    var updatedAt: String

    var hasSelection: Bool {
        applicationCount > 0 || categoryCount > 0 || webDomainCount > 0
    }

    var hasValidSelectionHash: Bool {
        selectionHash == Self.hash(selectionData: selectionData)
    }

    static func hash(selectionData: String) -> String {
        SHA256.hash(data: Data(selectionData.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

struct FamilyScreenTimeCatalogBinding: Codable, Equatable {
    var revision: Int
    var selectionHash: String
}

struct FamilyScreenTimeCatalogUpload: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = currentSchemaVersion
    var selectionData: String
    var selectionHash: String
    var applicationCount: Int
    var categoryCount: Int
    var webDomainCount: Int
    var capturedAt: String

    var hasSelection: Bool {
        applicationCount > 0 || categoryCount > 0 || webDomainCount > 0
    }

    var hasValidSelectionHash: Bool {
        selectionHash == FamilyScreenTimePolicy.hash(selectionData: selectionData)
    }
}

struct FamilyScreenTimeCatalog: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var revision: Int
    var selectionData: String
    var selectionHash: String
    var applicationCount: Int
    var categoryCount: Int
    var webDomainCount: Int
    var capturedAt: String
    var sourceDevicePublicRef: String

    var hasSelection: Bool {
        applicationCount > 0 || categoryCount > 0 || webDomainCount > 0
    }

    var hasValidSelectionHash: Bool {
        selectionHash == FamilyScreenTimePolicy.hash(selectionData: selectionData)
    }

    var binding: FamilyScreenTimeCatalogBinding {
        FamilyScreenTimeCatalogBinding(revision: revision, selectionHash: selectionHash)
    }
}

enum FamilyScreenTimeAuthorizationState: String, Codable, Equatable {
    case notRequested = "not_requested"
    case approved
    case denied
    case unavailable
    case error
}

enum FamilyScreenTimeEnforcementState: String, Codable, Equatable {
    case waitingForAuthorization = "waiting_for_authorization"
    case waitingForPolicy = "waiting_for_policy"
    case ready
    case applied
    case error
}

/// A child device acknowledgement. It intentionally contains no app names, bundle IDs,
/// usage history, or other Screen Time activity data.
struct FamilyScreenTimeDeviceStatus: Codable, Equatable {
    var authorization: FamilyScreenTimeAuthorizationState
    var enforcement: FamilyScreenTimeEnforcementState
    var appliedPolicyRevision: Int?
    var appliedSelectionHash: String? = nil
    var appliedControlCommandId: String? = nil
    var controlMode: FamilyScreenTimeControlMode? = nil
    var unlockedUntil: String? = nil
    var lastErrorCode: String?
    var applicationCount: Int? = nil
    var categoryCount: Int? = nil
    var webDomainCount: Int? = nil
    var updatedAt: String

    var hasSelection: Bool {
        (applicationCount ?? 0) > 0 || (categoryCount ?? 0) > 0 || (webDomainCount ?? 0) > 0
    }

    func acknowledgesCurrentLockedPolicy(
        _ policy: FamilyScreenTimePolicy,
        referenceDate: Date = Date()
    ) -> Bool {
        guard let control = policy.control else { return false }
        return authorization == .approved &&
            enforcement == .applied &&
            control.effectiveReceipt(referenceDate: referenceDate).mode == .locked &&
            controlMode == .locked &&
            appliedPolicyRevision == policy.revision &&
            appliedSelectionHash == policy.selectionHash &&
            appliedControlCommandId == control.commandId
    }

    static let waiting = FamilyScreenTimeDeviceStatus(
        authorization: .notRequested,
        enforcement: .waitingForAuthorization,
        appliedPolicyRevision: nil,
        appliedSelectionHash: nil,
        appliedControlCommandId: nil,
        controlMode: nil,
        unlockedUntil: nil,
        lastErrorCode: nil,
        applicationCount: 0,
        categoryCount: 0,
        webDomainCount: 0,
        updatedAt: ""
    )
}

struct FamilyScreenTimeRedemptionReceipt: Codable, Equatable {
    var redemptionRef: String
    var points: Int
    var minutes: Int
    var policyRevision: Int
    var selectionHash: String
    var controlCommandId: String
    var targetTokenHash: String
    var unlockUntil: String
}

struct FamilyScreenTimeRedemptionReservation: Codable, Equatable {
    enum State: String, Codable, Equatable {
        case reserved
        case committed
        case cancelled
        case expired
    }

    var id: String
    var redemptionRef: String
    var state: State
    var points: Int
    var expiresAt: String
    var balance: Int
}

struct GuardianScreenTimePolicyStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func policy(for childID: UUID) -> FamilyScreenTimePolicy? {
        guard let data = defaults.data(forKey: key(for: childID)) else { return nil }
        return try? JSONDecoder().decode(FamilyScreenTimePolicy.self, from: data)
    }

    func save(_ policy: FamilyScreenTimePolicy, for childID: UUID) throws {
        defaults.set(try JSONEncoder().encode(policy), forKey: key(for: childID))
    }

    func clear(for childID: UUID) {
        defaults.removeObject(forKey: key(for: childID))
    }

    private func key(for childID: UUID) -> String {
        "octoteacher.screentime.guardian-policy.\(childID.uuidString.lowercased())"
    }
}
