import Foundation

enum FamilyCloudClientError: LocalizedError, Equatable {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "云家庭返回了无法识别的数据。"
        case .server(let code): return FamilyCloudErrorMessage.localized(code)
        }
    }
}

private enum FamilyCloudErrorMessage {
    static func localized(_ code: String) -> String {
        switch code {
        case "email_device_code_expired": return "设备码已过期，请重新生成。"
        case "email_device_code_unavailable": return "这个设备码已使用或已失效，请重新生成。"
        case "email_device_code_not_found": return "没有找到这个设备码，请检查后重试。"
        case "email_device_rate_limited": return "生成设备码太频繁，请稍后再试。"
        case "invalid_email_device_request": return "手机登录请求无效，请重新开始连接。"
        case "guardian_consent_required": return "请先同意家庭同步与孩子任务同步。"
        case "invite_invalid_or_expired": return "二维码已使用或已过期，请重新生成。"
        case "guardian_session_required": return "监护人加入前需要先使用邮箱账号登录。"
        case "family_creator_required": return "只有家庭创建者可以执行这项操作。"
        case "family_deletion_confirmation_invalid": return "家庭删除确认信息不匹配。"
        case "stale_task_version": return "任务已在另一台设备更新，正在重新同步。"
        case "stale_child_profile_version": return "孩子设置已在另一台设备更新，正在重新同步。"
        case "child_device_update_required": return "这个孩子端版本已经停止联网，请先升级 App。"
        case "child_device_rebind_required": return "孩子端接口已经升级，需要由家长重新扫码绑定。"
        case "child_device_protocol_unsupported": return "孩子端与家庭服务器版本不兼容，请更新 App 后重试。"
        case "unauthorized": return "登录已失效，请重新登录。"
        default: return "云家庭暂时不可用（\(code)）。"
        }
    }
}

struct FamilyCloudClient {
    static let productionBaseURL = URL(string: "https://api.octoteacher.com/api/v1/")!
    static let childDeviceProtocolGeneration = 2

    var baseURL: URL = Self.productionBaseURL
    var session: URLSession = .shared

    func startEmailDeviceSession(
        deviceRef: String,
        deviceName: String
    ) async throws -> EmailDeviceLoginStart {
        try await send("auth/email/device/start", method: "POST", body: EmailDeviceLoginStartRequest(
            devicePublicRef: deviceRef,
            deviceName: deviceName
        ))
    }

    func exchangeEmailDeviceSession(
        requestToken: String,
        deviceRef: String
    ) async throws -> EmailDeviceLoginExchange {
        try await send("auth/email/device/exchange", method: "POST", body: EmailDeviceLoginExchangeRequest(
            requestToken: requestToken,
            devicePublicRef: deviceRef,
            consentVersion: FamilyCloudSessionStore.consentVersion,
            familySyncAccepted: true,
            childTaskSyncAccepted: true
        ))
    }

    func loadGuardianSession(token: String) async throws -> GuardianSessionStatus {
        try await send("auth/session", token: token)
    }

    func revokeGuardianSession(token: String) async throws {
        let _: SessionRevocationResponse = try await send("auth/session", method: "DELETE", token: token)
    }

    func createFamily(
        token: String,
        displayName: String,
        deviceName: String,
        children: [FamilyCreateChild]
    ) async throws -> FamilyCloudSnapshot {
        let response: FamilyResponse = try await send("families", method: "POST", token: token, body: FamilyCreateRequest(
            displayName: displayName,
            deviceName: deviceName,
            children: children,
            consentVersion: FamilyCloudSessionStore.consentVersion,
            familySyncAccepted: true,
            childTaskSyncAccepted: true
        ))
        return response.family
    }

    func issueInvite(token: String, familyId: String, kind: String, childId: String?) async throws -> FamilyCloudInvite {
        let response: InviteResponse = try await send(
            "families/\(familyId)/invites", method: "POST", token: token,
            body: InviteRequest(kind: kind, childProfileId: childId)
        )
        return response.invite
    }

    func createChild(token: String, familyId: String, child: FamilyCreateChild) async throws -> FamilyCloudSnapshot {
        let response: FamilyResponse = try await send(
            "families/\(familyId)/children", method: "POST", token: token, body: child
        )
        return response.family
    }

    func updateChild(
        token: String,
        familyId: String,
        childId: String,
        baseVersion: Int,
        child: FamilyCreateChild
    ) async throws -> FamilyCloudSnapshot {
        let response: FamilyResponse = try await send(
            "families/\(familyId)/children/\(childId)",
            method: "PUT",
            token: token,
            body: FamilyUpdateChild(baseVersion: baseVersion, child: child)
        )
        return response.family
    }

    func archiveChild(token: String, familyId: String, childId: String) async throws -> Bool {
        let response: ChildArchiveResponse = try await send(
            "families/\(familyId)/children/\(childId)/archive",
            method: "POST",
            token: token
        )
        return response.archived
    }

    func claimInvite(
        _ invite: FamilyCloudJoinPayload,
        guardianToken: String?,
        deviceRef: String,
        deviceName: String
    ) async throws -> InviteClaimResponse {
        try await send("family-invites/claim", method: "POST", token: guardianToken, body: InviteClaimRequest(
            publicRef: invite.publicRef,
            secret: invite.secret,
            devicePublicRef: deviceRef,
            deviceName: deviceName,
            consentVersion: invite.isGuardian ? FamilyCloudSessionStore.consentVersion : nil,
            familySyncAccepted: invite.isGuardian,
            childTaskSyncAccepted: invite.isGuardian,
            protocolGeneration: Self.childDeviceProtocolGeneration
        ))
    }

    func revokeDevice(token: String, familyId: String, deviceId: String) async throws -> FamilyCloudSnapshot {
        let response: FamilyResponse = try await send(
            "families/\(familyId)/devices/\(deviceId)/revoke", method: "POST", token: token
        )
        return response.family
    }

    func exportFamily(token: String, familyId: String) async throws -> FamilyCloudExport {
        let response: FamilyExportResponse = try await send("families/\(familyId)/export", token: token)
        return response.export
    }

    func deleteFamily(token: String, familyId: String, publicRef: String) async throws -> FamilyCloudDeletionReceipt {
        try await send(
            "families/\(familyId)", method: "DELETE", token: token,
            body: FamilyDeletionRequest(confirmation: "DELETE \(publicRef)")
        )
    }

    func loadGuardianTasks(token: String, familyId: String, cursor: Int64) async throws -> FamilyCloudTaskPage {
        let response: TasksResponse = try await send(
            "families/\(familyId)/tasks", token: token,
            queryItems: [URLQueryItem(name: "cursor", value: String(cursor))]
        )
        return response.page
    }

    func loadGuardianTaskSnapshot(token: String, familyId: String) async throws -> FamilyCloudTaskPage {
        let response: TasksResponse = try await send(
            "families/\(familyId)/tasks", token: token,
            queryItems: [URLQueryItem(name: "snapshot", value: "1")]
        )
        return response.page
    }

    func loadGuardianActivitySummary(
        token: String,
        familyId: String,
        childId: String,
        days: Int = 90,
        localDate: String? = nil,
        timeZone: String = TimeZone.current.identifier
    ) async throws -> FamilyCloudActivitySummary {
        var queryItems = [
            URLQueryItem(name: "days", value: String(days)),
            URLQueryItem(name: "timeZone", value: timeZone),
        ]
        if let localDate {
            queryItems.append(URLQueryItem(name: "date", value: localDate))
        }
        return try await send(
            "families/\(familyId)/children/\(childId)/activity-summary",
            token: token,
            queryItems: queryItems
        )
    }

    func loadGuardianChildSurface(
        token: String,
        familyId: String,
        childId: String
    ) async throws -> FamilyChildSurface {
        let response: ChildSurfaceEnvelope = try await send(
            "families/\(familyId)/children/\(childId)/surface",
            token: token
        )
        return response.surface
    }

    func syncTasks(
        token: String,
        familyId: String,
        mutationRef: String,
        cursor: Int64,
        tasks: [FamilyCloudTaskUpload]
    ) async throws -> FamilyCloudTaskPage {
        let response: TasksResponse = try await send(
            "families/\(familyId)/tasks", method: "POST", token: token,
            body: TasksUpload(mutationRef: mutationRef, cursor: cursor, tasks: tasks)
        )
        return response.page
    }

    func loadChildTasks(token: String, cursor: Int64) async throws -> FamilyCloudTaskPage {
        let response: TasksResponse = try await send(
            "device/tasks", token: token,
            queryItems: [URLQueryItem(name: "cursor", value: String(cursor))]
        )
        return response.page
    }

    func loadChildTaskSnapshot(token: String) async throws -> FamilyCloudTaskPage {
        let response: TasksResponse = try await send(
            "device/tasks", token: token,
            queryItems: [URLQueryItem(name: "snapshot", value: "1")]
        )
        return response.page
    }

    func loadChildSurface(token: String) async throws -> FamilyChildSurface {
        let response: ChildSurfaceEnvelope = try await send("device/surface", token: token)
        return response.surface
    }

    func loadChildProfile(token: String) async throws -> ChildDeviceProfileResponse {
        let response: ChildProfileEnvelope = try await send("device/profile", token: token)
        return response.child
    }

    func updateChildInterfaceLanguage(
        token: String,
        language: AppInterfaceLanguage
    ) async throws -> ChildDeviceProfileResponse {
        let response: ChildProfileEnvelope = try await send(
            "device/profile",
            method: "PUT",
            token: token,
            body: ChildInterfaceLanguageUpdateRequest(interfaceLanguage: language)
        )
        return response.child
    }

    func updateScreenTimePolicy(
        token: String,
        familyId: String,
        childProfileId: String,
        policy: FamilyScreenTimePolicy?
    ) async throws -> FamilyCloudSnapshot {
        let response: FamilyResponse = try await send(
            "families/\(familyId)/screen-time",
            method: "PUT",
            token: token,
            body: GuardianScreenTimePolicyRequest(childProfileId: childProfileId, policy: policy)
        )
        return response.family
    }

    func updateChildScreenTimeStatus(
        token: String,
        status: FamilyScreenTimeDeviceStatus
    ) async throws -> ChildDeviceProfileResponse {
        let response: ChildProfileEnvelope = try await send(
            "device/screen-time/status",
            method: "PUT",
            token: token,
            body: status
        )
        return response.child
    }

    func updateChildScreenTimeCatalog(
        token: String,
        catalog: FamilyScreenTimeCatalogUpload
    ) async throws -> ChildDeviceProfileResponse {
        let response: ChildProfileEnvelope = try await send(
            "device/screen-time/selection",
            method: "PUT",
            token: token,
            body: catalog
        )
        return response.child
    }

    func registerChildPush(
        token: String,
        registration: FamilyRemotePushRegistration
    ) async throws -> ChildDeviceProfileResponse {
        let response: ChildProfileEnvelope = try await send(
            "device/push",
            method: "PUT",
            token: token,
            body: ChildPushRegistrationRequest(
                token: registration.token,
                environment: registration.environment.rawValue
            )
        )
        return response.child
    }

    func updateGuardianScreenTimeControl(
        token: String,
        familyId: String,
        childProfileId: String,
        action: String,
        minutes: Int?
    ) async throws -> FamilyCloudSnapshot {
        let response: FamilyResponse = try await send(
            "families/\(familyId)/screen-time/control",
            method: "PUT",
            token: token,
            body: GuardianScreenTimeControlRequest(
                childProfileId: childProfileId,
                action: action,
                minutes: minutes
            )
        )
        return response.family
    }

    func updateGuardianScreenTimeEmergency(
        token: String,
        familyId: String,
        childProfileId: String,
        action: String,
        requestId: String,
        minutes: Int? = nil
    ) async throws -> FamilyCloudSnapshot {
        let response: FamilyResponse = try await send(
            "families/\(familyId)/screen-time/emergency",
            method: "PUT",
            token: token,
            body: GuardianScreenTimeEmergencyRequest(
                childProfileId: childProfileId,
                action: action,
                requestId: requestId,
                minutes: minutes
            )
        )
        return response.family
    }

    func updateChildScreenTimeEmergency(
        token: String,
        action: String,
        requestId: String,
        reason: String? = nil,
        minutes: Int? = nil,
        sessionEndsAt: String? = nil
    ) async throws -> ChildDeviceProfileResponse {
        let response: ChildProfileEnvelope = try await send(
            "device/screen-time/emergency",
            method: "PUT",
            token: token,
            body: ChildScreenTimeEmergencyRequest(
                action: action,
                requestId: requestId,
                reason: reason,
                minutes: minutes,
                sessionEndsAt: sessionEndsAt
            )
        )
        return response.child
    }

    func configureFamilyAI(
        token: String,
        familyId: String,
        provisioning: FamilyAIProviderProvisioning
    ) async throws -> FamilyAICapabilities {
        let response: FamilyAIEnvelope = try await send(
            "families/\(familyId)/ai",
            method: "PUT",
            token: token,
            body: provisioning
        )
        return response.ai
    }

    func loadChildAICapabilities(token: String) async throws -> FamilyAICapabilities {
        let response: FamilyAIEnvelope = try await send("device/ai/status", token: token)
        return response.ai
    }

    func completeChildAIChat(
        token: String,
        request: FamilyAIChatRelayRequest
    ) async throws -> String {
        let response: FamilyAIChatRelayResponse = try await send(
            "device/ai/chat",
            method: "POST",
            token: token,
            body: request
        )
        return response.content
    }

    func transcribeChildAIAudio(
        token: String,
        request: FamilyAITranscriptionRelayRequest
    ) async throws -> String {
        let response: FamilyAITranscriptionRelayResponse = try await send(
            "device/ai/transcribe",
            method: "POST",
            token: token,
            body: request
        )
        return response.text
    }

    func submitChildTask(
        token: String,
        taskId: String,
        mutationRef: String,
        expectedVersion: Int,
        evidenceSummary: String?
    ) async throws -> FamilyCloudTask {
        let response: TaskResponse = try await send(
            "device/tasks/\(taskId)/submit", method: "POST", token: token,
            body: TaskSubmitRequest(
                mutationRef: mutationRef,
                expectedVersion: expectedVersion,
                evidenceSummary: evidenceSummary
            )
        )
        return response.task
    }

    func withdrawChildTask(
        token: String,
        taskId: String,
        mutationRef: String,
        expectedVersion: Int
    ) async throws -> FamilyCloudTask {
        let response: TaskResponse = try await send(
            "device/tasks/\(taskId)/withdraw", method: "POST", token: token,
            body: TaskWithdrawalRequest(
                mutationRef: mutationRef,
                expectedVersion: expectedVersion
            )
        )
        return response.task
    }

    func applyChildPointMutation(
        token: String,
        mutation: PendingFamilyCloudPointMutation
    ) async throws -> FamilyCloudPointMutationResponse {
        try await send(
            "device/points/mutations",
            method: "POST",
            token: token,
            body: PointMutationRequest(
                mutationRef: mutation.mutationRef,
                kind: mutation.kind,
                delta: mutation.delta,
                sourceRef: mutation.sourceRef
            )
        )
    }

    func reserveScreenTimeRedemption(
        token: String,
        receipt: FamilyScreenTimeRedemptionReceipt
    ) async throws -> FamilyScreenTimeRedemptionReservation {
        try await send(
            "device/screen-time/redemptions",
            method: "POST",
            token: token,
            body: receipt
        )
    }

    func commitScreenTimeRedemption(
        token: String,
        reservationID: String,
        receipt: FamilyScreenTimeRedemptionReceipt
    ) async throws -> FamilyScreenTimeRedemptionReservation {
        try await send(
            "device/screen-time/redemptions/\(reservationID)/commit",
            method: "POST",
            token: token,
            body: receipt
        )
    }

    func cancelScreenTimeRedemption(
        token: String,
        reservationID: String
    ) async throws -> FamilyScreenTimeRedemptionReservation {
        try await send(
            "device/screen-time/redemptions/\(reservationID)/cancel",
            method: "POST",
            token: token
        )
    }

    func createPortalLink(token: String, familyId: String) async throws -> FamilyCloudPortalLink {
        try await send("families/\(familyId)/portal-link", method: "POST", token: token)
    }

    func uploadChildActivityEvents(
        token: String,
        events: [PendingFamilyCloudActivityEvent]
    ) async throws -> FamilyCloudActivityUploadResponse {
        try await send(
            "device/activity/events",
            method: "POST",
            token: token,
            body: FamilyCloudActivityUploadRequest(events: events)
        )
    }

    private func send<Response: Decodable>(
        _ path: String,
        method: String = "GET",
        token: String? = nil,
        headers: [String: String] = [:],
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        try await send(
            path, method: method, token: token, headers: headers,
            queryItems: queryItems, bodyData: nil
        )
    }

    private func send<Response: Decodable, Body: Encodable>(
        _ path: String,
        method: String,
        token: String? = nil,
        headers: [String: String] = [:],
        queryItems: [URLQueryItem] = [],
        body: Body
    ) async throws -> Response {
        try await send(
            path, method: method, token: token, headers: headers,
            queryItems: queryItems, bodyData: try JSONEncoder().encode(body)
        )
    }

    private func send<Response: Decodable>(
        _ path: String,
        method: String,
        token: String?,
        headers: [String: String],
        queryItems: [URLQueryItem],
        bodyData: Data?
    ) async throws -> Response {
        let endpoint = baseURL.appendingPathComponent(path)
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else { throw FamilyCloudClientError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            String(Self.childDeviceProtocolGeneration),
            forHTTPHeaderField: "X-Octo-Child-Protocol"
        )
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let bodyData {
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FamilyCloudClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let error = (try? JSONDecoder().decode(ServerError.self, from: data).error) ?? "http_\(http.statusCode)"
            throw FamilyCloudClientError.server(error)
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw FamilyCloudClientError.invalidResponse
        }
        return decoded
    }
}

struct FamilyCreateChild: Codable {
    var clientRef: String
    var displayName: String
    var birthYear: Int?
    var preReaderMode: Bool
    var interfaceLanguage: AppInterfaceLanguage
    var contentLanguage: FamilyLanguage
    var dailyLimitMinutes: Int
    var exchangePolicy: FamilyExchangePolicy
}
private struct FamilyUpdateChild: Codable {
    var baseVersion: Int
    var clientRef: String
    var displayName: String
    var birthYear: Int?
    var preReaderMode: Bool
    var interfaceLanguage: AppInterfaceLanguage
    var contentLanguage: FamilyLanguage
    var dailyLimitMinutes: Int
    var exchangePolicy: FamilyExchangePolicy

    init(baseVersion: Int, child: FamilyCreateChild) {
        self.baseVersion = baseVersion
        clientRef = child.clientRef
        displayName = child.displayName
        birthYear = child.birthYear
        preReaderMode = child.preReaderMode
        interfaceLanguage = child.interfaceLanguage
        contentLanguage = child.contentLanguage
        dailyLimitMinutes = child.dailyLimitMinutes
        exchangePolicy = child.exchangePolicy
    }
}
struct GuardianSessionResponse: Codable { var sessionToken: String; var expiresAt: String; var guardian: GuardianSummary; var family: FamilyCloudSnapshot? }
struct GuardianSessionStatus: Codable { var guardian: GuardianSummary; var family: FamilyCloudSnapshot? }
struct GuardianSummary: Codable { var id: String; var displayName: String? }
struct EmailDeviceLoginStart: Codable, Equatable {
    var code: String
    var requestToken: String
    var verificationURL: URL
    var expiresAt: String
}
struct EmailDeviceLoginExchange: Codable {
    var status: String
    var sessionToken: String?
    var expiresAt: String?
    var guardian: GuardianSummary?
    var family: FamilyCloudSnapshot?
}
struct InviteClaimResponse: Codable {
    var kind: String
    var deviceSessionToken: String?
    var family: FamilyCloudSnapshot?
    var child: FamilyCloudSnapshot.Child?
    private enum CodingKeys: String, CodingKey { case kind, deviceSessionToken, family, child }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        deviceSessionToken = try container.decodeIfPresent(String.self, forKey: .deviceSessionToken)
        child = try container.decodeIfPresent(FamilyCloudSnapshot.Child.self, forKey: .child)
        family = try? container.decodeIfPresent(FamilyCloudSnapshot.self, forKey: .family)
    }
}

private struct EmailDeviceLoginStartRequest: Codable { var devicePublicRef: String; var deviceName: String }
private struct EmailDeviceLoginExchangeRequest: Codable {
    var requestToken: String
    var devicePublicRef: String
    var consentVersion: String
    var familySyncAccepted: Bool
    var childTaskSyncAccepted: Bool
}
private struct FamilyCreateRequest: Codable { var displayName: String; var deviceName: String; var children: [FamilyCreateChild]; var consentVersion: String; var familySyncAccepted: Bool; var childTaskSyncAccepted: Bool }
private struct FamilyResponse: Codable { var family: FamilyCloudSnapshot }
private struct ChildArchiveResponse: Codable { var archived: Bool }
private struct InviteRequest: Codable { var kind: String; var childProfileId: String? }
private struct InviteResponse: Codable { var invite: FamilyCloudInvite }
private struct InviteClaimRequest: Codable {
    var publicRef: String
    var secret: String
    var devicePublicRef: String
    var deviceName: String
    var consentVersion: String?
    var familySyncAccepted: Bool
    var childTaskSyncAccepted: Bool
    var protocolGeneration: Int
}
private struct TasksUpload: Codable { var mutationRef: String; var cursor: Int64; var tasks: [FamilyCloudTaskUpload] }
private struct SessionRevocationResponse: Codable { var revoked: Bool }
private struct FamilyExportResponse: Codable { var export: FamilyCloudExport }
private struct FamilyDeletionRequest: Codable { var confirmation: String }
private struct TasksResponse: Codable {
    var tasks: [FamilyCloudTask]
    var removedClientRefs: [String]?
    var cursor: Int64?
    var hasMore: Bool?
    var page: FamilyCloudTaskPage {
        FamilyCloudTaskPage(
            tasks: tasks,
            removedClientRefs: removedClientRefs ?? [],
            cursor: cursor ?? 0,
            hasMore: hasMore ?? false
        )
    }
}
private struct TaskResponse: Codable { var task: FamilyCloudTask }
private struct ChildProfileEnvelope: Codable { var child: ChildDeviceProfileResponse }
private struct ChildSurfaceEnvelope: Codable { var surface: FamilyChildSurface }
private struct ChildInterfaceLanguageUpdateRequest: Codable {
    var interfaceLanguage: AppInterfaceLanguage
}
private struct ChildPushRegistrationRequest: Codable {
    var token: String
    var environment: String
}
private struct GuardianScreenTimePolicyRequest: Codable {
    var childProfileId: String
    var policy: FamilyScreenTimePolicy?
}
private struct GuardianScreenTimeControlRequest: Codable {
    var childProfileId: String
    var action: String
    var minutes: Int?
}
private struct GuardianScreenTimeEmergencyRequest: Codable {
    var childProfileId: String
    var action: String
    var requestId: String
    var minutes: Int?
}
private struct ChildScreenTimeEmergencyRequest: Codable {
    var action: String
    var requestId: String
    var reason: String?
    var minutes: Int?
    var sessionEndsAt: String?
}
private struct FamilyAIEnvelope: Codable { var ai: FamilyAICapabilities }
private struct FamilyAIChatRelayResponse: Codable { var content: String }
private struct FamilyAITranscriptionRelayResponse: Codable { var text: String }
private struct TaskSubmitRequest: Codable { var mutationRef: String; var expectedVersion: Int; var evidenceSummary: String? }
private struct TaskWithdrawalRequest: Codable { var mutationRef: String; var expectedVersion: Int }
private struct PointMutationRequest: Codable {
    var mutationRef: String
    var kind: FamilyCloudPointMutationKind
    var delta: Int
    var sourceRef: String
}
private struct FamilyCloudActivityUploadRequest: Codable {
    var events: [PendingFamilyCloudActivityEvent]
}
private struct ServerError: Codable { var error: String }
