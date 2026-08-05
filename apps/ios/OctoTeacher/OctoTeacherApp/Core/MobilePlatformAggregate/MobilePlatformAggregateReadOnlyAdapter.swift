import Foundation

/// Read-only adapter for the mobile platform aggregate.
///
/// This is the iOS-side boundary for a future cloud permission gateway. Today it only
/// composes local mock snapshots and exposes safe display models; it never calls
/// network, AI, StoreKit, FamilyControls, ledger, school, or device services.
struct MobilePlatformAggregateReadOnlyAdapter {
    let chargesPayment = false
    let createsOrder = false
    let writesMarketplace = false
    let writesEntitlement = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false
    let callsCloud = false
    let callsAi = false
    let writesSchoolSystem = false

    private let snapshotBuilder: MobilePlatformAggregateSnapshotBuilder
    private let growthPackInstallBuilder: GrowthPackInstallEntitlementBuilder

    init(
        snapshotBuilder: MobilePlatformAggregateSnapshotBuilder = MobilePlatformAggregateSnapshotBuilder(),
        growthPackInstallBuilder: GrowthPackInstallEntitlementBuilder = GrowthPackInstallEntitlementBuilder()
    ) {
        self.snapshotBuilder = snapshotBuilder
        self.growthPackInstallBuilder = growthPackInstallBuilder
    }

    func makeSnapshot(
        viewerRole: MobilePlatformAggregateViewerRole,
        mobileSnapshot: MobileSyncSnapshot,
        familyAchievement: FamilyAchievementSnapshotDashboard,
        growthPack: GrowthPackMobileDetailSnapshot,
        schoolCredit: SchoolGrowthCreditSnapshot,
        offlineStatus: MobileOfflinePublicStatus = .clean,
        offlineReport: MobileOfflineReplayReport = .empty,
        creditSettlement: MobileCreditSettlementReport = .empty,
        growthPackInstall: GrowthPackInstallSnapshot? = nil
    ) -> MobilePlatformAggregateSnapshot {
        snapshotBuilder.build(
            viewerRole: viewerRole,
            mobileSnapshot: mobileSnapshot,
            familyAchievement: familyAchievement,
            growthPack: growthPack,
            schoolCredit: schoolCredit,
            offlineStatus: offlineStatus,
            offlineReport: offlineReport,
            creditSettlement: creditSettlement,
            growthPackInstall: growthPackInstall ?? growthPackInstallBuilder.build(viewerRole: installRole(for: viewerRole))
        )
    }

    func growthPackInstallDisplay(
        from snapshot: MobilePlatformAggregateSnapshot
    ) -> MobilePlatformAggregateGrowthPackInstallDisplay {
        let summary = snapshot.growthPackInstall
        guard summary.visible else {
            return .hidden
        }

        let metrics = [
            MobilePlatformAggregateInstallMetric(label: "可见", value: summary.visiblePackCount),
            MobilePlatformAggregateInstallMetric(label: "已安装", value: summary.installedCount),
            MobilePlatformAggregateInstallMetric(label: "可安装", value: summary.installableCount),
            MobilePlatformAggregateInstallMetric(label: "待确认", value: summary.pendingGuardianCount),
            MobilePlatformAggregateInstallMetric(label: "冻结", value: summary.frozenCount),
            MobilePlatformAggregateInstallMetric(label: "阻断", value: summary.blockedCount),
            MobilePlatformAggregateInstallMetric(label: "需关注", value: summary.needsGuardianAttentionCount)
        ]

        let isGuardian = snapshot.header.viewerRole == .guardian
        let detail: String
        if isGuardian, summary.needsGuardianAttentionCount > 0 {
            detail = "有 \(summary.needsGuardianAttentionCount) 个成长包安装权益需要家长复核。"
        } else if snapshot.header.viewerRole == .child, summary.needsGuardianAttentionCount > 0 {
            detail = "等待家长确认成长包安装后继续挑战。"
        } else {
            detail = "成长包安装权益保持只读同步。"
        }

        return MobilePlatformAggregateGrowthPackInstallDisplay(
            visible: true,
            title: "成长包安装权益",
            detail: detail,
            metrics: metrics,
            actionRequired: isGuardian && summary.needsGuardianAttentionCount > 0,
            chargesPayment: summary.chargesPayment || chargesPayment,
            createsOrder: summary.createsOrder || createsOrder,
            writesMarketplace: summary.writesMarketplace || writesMarketplace,
            writesEntitlement: summary.writesEntitlement || writesEntitlement,
            writesLedger: summary.writesLedger || writesLedger,
            grantsCredit: summary.grantsCredit || grantsCredit,
            unlocksDevice: summary.unlocksDevice || unlocksDevice,
            callsCloud: summary.callsCloud || callsCloud,
            callsAi: summary.callsAi || callsAi,
            writesSchoolSystem: summary.writesSchoolSystem || writesSchoolSystem
        )
    }

    static func redacts(_ display: MobilePlatformAggregateGrowthPackInstallDisplay) -> Bool {
        let values = [display.title, display.detail] + display.metrics.flatMap { [$0.label, "\($0.value)"] }
        let joined = values.joined(separator: " ").lowercased()
        let blockedMarkers = [
            "child:", "family:", "school:", "teacher:", "relative:", "pack:", "creator:",
            "order:", "entitlement:", "gpi-order", "gpi-ent", "http://", "https://",
            "file://", "/users/", "/volumes/", "192.168.", "token", "secret"
        ]
        if blockedMarkers.contains(where: { joined.contains($0) }) { return false }
        let blockedPatterns = [
            #"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"#,
            #"(?i)\b[0-9a-f]{24,}\b"#,
            #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#
        ]
        return !blockedPatterns.contains { pattern in
            joined.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private func installRole(for role: MobilePlatformAggregateViewerRole) -> GrowthPackInstallViewerRole {
        switch role {
        case .child:
            return .child
        case .guardian:
            return .guardian
        case .relative, .teacher:
            return .relative
        }
    }
}

struct MobilePlatformAggregateInstallMetric: Equatable, Identifiable {
    var label: String
    var value: Int

    var id: String { label }
}

struct MobilePlatformAggregateGrowthPackInstallDisplay: Equatable {
    var visible: Bool
    var title: String
    var detail: String
    var metrics: [MobilePlatformAggregateInstallMetric]
    var actionRequired: Bool

    let chargesPayment: Bool
    let createsOrder: Bool
    let writesMarketplace: Bool
    let writesEntitlement: Bool
    let writesLedger: Bool
    let grantsCredit: Bool
    let unlocksDevice: Bool
    let callsCloud: Bool
    let callsAi: Bool
    let writesSchoolSystem: Bool

    static let hidden = MobilePlatformAggregateGrowthPackInstallDisplay(
        visible: false,
        title: "",
        detail: "",
        metrics: [],
        actionRequired: false,
        chargesPayment: false,
        createsOrder: false,
        writesMarketplace: false,
        writesEntitlement: false,
        writesLedger: false,
        grantsCredit: false,
        unlocksDevice: false,
        callsCloud: false,
        callsAi: false,
        writesSchoolSystem: false
    )
}
