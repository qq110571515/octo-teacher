import Foundation
import ManagedSettings

final class ShieldActionExtension: ShieldActionDelegate {
    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        persist(action: action, targetKind: .application, token: application)
        completionHandler(responseThatOpensApp())
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        persist(action: action, targetKind: .category, token: category)
        completionHandler(responseThatOpensApp())
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        persist(action: action, targetKind: .webDomain, token: webDomain)
        completionHandler(responseThatOpensApp())
    }

    private func persist<Token: Encodable>(
        action: ShieldAction,
        targetKind: PersistedShieldTargetKind,
        token: Token
    ) {
        guard let defaults = UserDefaults(suiteName: ScreenTimeSharedContract.appGroupIdentifier),
              let tokenData = try? PropertyListEncoder().encode(token)
        else { return }
        let schoolIsActive = defaults.bool(forKey: ScreenTimeSharedContract.schoolModeActiveKey)
        let intent: PersistedShieldActionIntent
        switch action {
        case .primaryButtonPressed:
            intent = schoolIsActive ? .requestSchoolEmergency : .redeemGrowthPoints
        case .secondaryButtonPressed:
            intent = .parentPIN
        default:
            intent = schoolIsActive ? .requestSchoolEmergency : .redeemGrowthPoints
        }
        let request = PersistedShieldActionRequest(
            id: UUID(),
            intent: intent,
            targetKind: targetKind,
            tokenData: tokenData,
            createdAt: Date(),
            interfaceLanguageRawValue: ScreenTimeSharedContract.resolvedChildInterfaceLanguageRawValue(
                defaults: defaults
            ),
            selectionGeneration: ScreenTimeSharedContract.currentSelectionGeneration(
                defaults: defaults
            )
        )
        guard let data = try? JSONEncoder().encode(request) else { return }
        defaults.set(data, forKey: ScreenTimeSharedContract.pendingShieldActionKey)
        guard defaults.synchronize(),
              defaults.data(forKey: ScreenTimeSharedContract.pendingShieldActionKey) == data
        else { return }
        ScreenTimeOperationAuditLedger.append(
            PersistedScreenTimeOperationAuditEntry(
                id: UUID(),
                requestID: request.id,
                stage: "shield_request_received",
                outcome: .started,
                authorityRawValue: nil,
                targetKind: targetKind,
                interfaceLanguageRawValue: request.validatedInterfaceLanguageRawValue,
                durationMinutes: nil,
                errorCode: nil,
                timestamp: request.createdAt
            ),
            defaults: defaults
        )
    }

    private func responseThatOpensApp() -> ShieldActionResponse {
        if #available(iOS 26.5, *) {
            return .openParentalControlsApp
        }
        return .close
    }
}
