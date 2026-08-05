import Foundation

/// 家庭网络只保留三类产品角色。家庭创建者仍是监护人，只额外拥有成员管理权。
enum FamilyMemberRole: String, Codable, CaseIterable {
    case guardian
    case relative
    case child

    var label: String {
        switch self {
        case .guardian: return "监护人"
        case .relative: return "亲友"
        case .child: return "孩子"
        }
    }
}
enum FamilyMemberStatus: String, Codable {
    case active
    case pending
    case revoked
}

/// 家庭中的逻辑成员。称谓只是展示信息，权限只由 role 决定。
struct FamilyNetworkMember: Identifiable, Codable, Equatable {
    let id: UUID
    var displayName: String
    var role: FamilyMemberRole
    var kinshipLabel: String?
    var childId: UUID?
    var status: FamilyMemberStatus
    var joinedAt: Date
}

enum FamilyDeviceBindingStatus: String, Codable {
    case pendingCloudVerification
    case active
    case revoked
}

/// 一台手机与家庭成员的绑定。孩子设备只绑定一个 childId，不要求邮箱账号。
struct FamilyDeviceBinding: Identifiable, Codable, Equatable {
    let id: UUID
    var memberId: UUID
    var role: FamilyMemberRole
    var childId: UUID?
    var deviceName: String
    var status: FamilyDeviceBindingStatus
    var boundAt: Date
}

enum FamilyJoinInviteStatus: String, Codable {
    case issued
    case claimed
    case revoked
    case expired
}

/// 创建者签发的一次性加入邀请。token 只进入二维码与本机快照，不写日志。
struct FamilyJoinInvite: Identifiable, Codable, Equatable {
    let id: UUID
    var role: FamilyMemberRole
    var childId: UUID?
    var suggestedDisplayName: String?
    var token: String
    var status: FamilyJoinInviteStatus
    var createdAt: Date
    var expiresAt: Date

    func resolvedStatus(at date: Date = Date()) -> FamilyJoinInviteStatus {
        status == .issued && expiresAt <= date ? .expired : status
    }
}

/// 二维码里的最小设备配置合同。真正跨设备同步仍须由后台验证 token 并下发数据。
struct FamilyJoinPayload: Codable, Equatable {
    static let currentVersion = 1
    static let schemePrefix = "octoteacher://family/join/"

    var version: Int
    var familyId: UUID
    var familyName: String
    var inviteId: UUID
    var token: String
    var role: FamilyMemberRole
    var childId: UUID?
    var suggestedDisplayName: String?
    var expiresAt: Date

    var encodedValue: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return nil }
        let payload = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return Self.schemePrefix + payload
    }

    static func decode(_ rawValue: String) -> FamilyJoinPayload? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(schemePrefix) else { return nil }
        var base64 = String(trimmed.dropFirst(schemePrefix.count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONDecoder().decode(FamilyJoinPayload.self, from: data),
              payload.version == currentVersion else { return nil }
        return payload
    }
}

/// 本地家庭网络快照。它是未来云端 household/member/device/invite 表的移动端合同。
struct FamilyNetworkState: Codable, Equatable {
    var familyId: UUID
    var familyName: String
    var creatorMemberId: UUID
    var members: [FamilyNetworkMember]
    var devices: [FamilyDeviceBinding]
    var invitations: [FamilyJoinInvite]
    var currentDeviceId: UUID

    func activeMembers(role: FamilyMemberRole? = nil) -> [FamilyNetworkMember] {
        members.filter { member in
            member.status == .active && (role == nil || member.role == role)
        }
    }

    func member(id: UUID) -> FamilyNetworkMember? {
        members.first { $0.id == id }
    }
}
