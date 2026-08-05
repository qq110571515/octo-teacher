import Foundation

/// Local, read-only permission gateway adapter for the mobile platform.
///
/// This is a mock boundary for the future cloud/iOS permission gateway. It only
/// composes already-redacted local snapshots into safe display gates; it never
/// calls FamilyControls, StoreKit, network, AI, LMS, ledger, device unlock, or
/// school systems.
struct MobilePlatformPermissionGatewayAdapter {
    let sideEffects = MobilePlatformPermissionGatewaySideEffects()

    func build(
        viewerRole: MobilePlatformPermissionGatewayViewerRole,
        home: MobileHomeViewModel? = nil,
        aggregate: MobilePlatformAggregateSnapshot? = nil,
        unsafePayload: [String] = []
    ) -> MobilePlatformPermissionGatewaySnapshot {
        if containsUnsafePayload(unsafePayload) {
            return safeBlockedSnapshot(viewerRole: viewerRole)
        }

        let gates = gateTemplates(for: viewerRole, home: home, aggregate: aggregate)
        let snapshot = MobilePlatformPermissionGatewaySnapshot(
            generatedAt: generatedAt(from: aggregate),
            viewerRole: viewerRole,
            gates: gates,
            publicSummary: MobilePlatformPermissionGatewayPublicSummary(gates: gates),
            sideEffects: sideEffects
        )
        return Self.redacts(snapshot) ? snapshot : safeBlockedSnapshot(viewerRole: viewerRole)
    }

    func homeItems(from snapshot: MobilePlatformPermissionGatewaySnapshot) -> [MobileHomeItem] {
        snapshot.gates.map { gate in
            MobileHomeItem(
                id: "permission-gate-\(gate.kind.rawValue)",
                title: gate.title,
                detail: gate.detail,
                systemImage: icon(for: gate.kind, state: gate.state),
                tone: tone(for: gate.state),
                badge: gate.state.label
            )
        }
    }

    func buildReadModel(
        viewerRole: MobilePlatformPermissionGatewayViewerRole,
        platform: MobilePlatformPermissionGatewayPlatform = .ios,
        home: MobileHomeViewModel? = nil,
        aggregate: MobilePlatformAggregateSnapshot? = nil,
        unsafePayload: [String] = []
    ) -> MobilePlatformPermissionGatewayReadModelReport {
        if containsUnsafePayload(unsafePayload) {
            return safeBlockedReadModel(viewerRole: viewerRole, platform: platform)
        }

        let gates = gateTemplates(for: viewerRole, home: home, aggregate: aggregate)
        let modules = moduleReadModels(
            for: viewerRole,
            gates: gates,
            home: home,
            aggregate: aggregate
        )
        let findings = moduleFindings(modules)
        let report = MobilePlatformPermissionGatewayReadModelReport(
            accepted: !findings.contains { $0.severity == .blocker },
            generatedAt: generatedAt(from: aggregate),
            state: readModelState(modules),
            viewer: MobilePlatformPermissionGatewayViewerReadModel(
                actorPublicRef: "viewer-\(viewerRole.rawValue)",
                childPublicRef: viewerRole == .child ? "child-current" : nil,
                role: viewerRole,
                platform: platform,
                offline: isOffline(home: home, aggregate: aggregate),
                authorizedChildCount: viewerRole == .child ? 1 : 0
            ),
            modules: modules,
            findings: findings,
            nextActions: nextActions(from: modules),
            publicSummary: MobilePlatformPermissionGatewayReadModelPublicSummary(
                generatedAt: generatedAt(from: aggregate),
                gatewayPublicRef: "mpg-gateway",
                viewerPublicRef: "viewer-\(viewerRole.rawValue)",
                childPublicRef: viewerRole == .child ? "child-current" : nil,
                familyPublicRef: "family-current",
                state: readModelState(modules),
                viewerRole: viewerRole,
                platform: platform,
                modules: modules,
                findingCodes: findings.map(\.code)
            ),
            sideEffects: MobilePlatformPermissionGatewayReadModelSideEffects()
        )

        return Self.redacts(report) ? report : safeBlockedReadModel(viewerRole: viewerRole, platform: platform)
    }

    func homeItems(from report: MobilePlatformPermissionGatewayReadModelReport) -> [MobileHomeItem] {
        report.modules
            .filter { $0.visibility != .hidden }
            .map { module in
                MobileHomeItem(
                    id: "permission-module-\(module.module.rawValue)",
                    title: module.module.title,
                    detail: module.visibility.detail,
                    systemImage: icon(for: module.module, visibility: module.visibility),
                    tone: tone(for: module.visibility),
                    badge: module.visibility.label
                )
            }
    }

    static func redacts(_ snapshot: MobilePlatformPermissionGatewaySnapshot) -> Bool {
        let values = snapshot.displayValues
        if MobileSyncPayloadGuard.isUnsafe(values) { return false }
        let joined = values.joined(separator: " ").lowercased()
        let blockedMarkers = [
            "child:", "family:", "school:", "teacher:", "relative:", "guardian:",
            "task:", "proof:", "decision:", "hold:", "reward:", "feed:",
            "pack:", "creator:", "order:", "entitlement:", "gpi-order", "gpi-ent",
            "provider:", "model:", "baseurl", "api_key", "apikey", "token", "secret",
            "http://", "https://", "file://", "/users/", "/volumes/", "192.168."
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

    static func redacts(_ report: MobilePlatformPermissionGatewayReadModelReport) -> Bool {
        let values = report.displayValues
        if MobileSyncPayloadGuard.isUnsafe(values) { return false }
        let joined = values.joined(separator: " ").lowercased()
        let blockedMarkers = [
            "child:", "family:", "school:", "teacher:", "relative:", "guardian:",
            "task:", "proof:", "decision:", "hold:", "reward:", "feed:",
            "pack:", "creator:", "order:", "entitlement:", "gpi-order", "gpi-ent",
            "provider:", "model:", "baseurl", "api_key", "apikey", "token", "secret",
            "http://", "https://", "file://", "/users/", "/volumes/", "192.168."
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

    private func gateTemplates(
        for role: MobilePlatformPermissionGatewayViewerRole,
        home: MobileHomeViewModel?,
        aggregate: MobilePlatformAggregateSnapshot?
    ) -> [MobilePlatformPermissionGate] {
        let homeSectionIds = Set(home?.sections.map(\.id) ?? [])
        let homeMetricIds = Set(home?.metrics.map(\.id) ?? [])
        let roleVisibility = aggregate?.roleVisibility
        let growthInstallAttention = aggregate?.growthPackInstall.needsGuardianAttentionCount
            ?? metricValue("growth-pack-entitlements", from: home)
            ?? 0
        let offlineConflicts = (aggregate?.offlineSync.conflictCount ?? 0) + (aggregate?.offlineSync.rollbackRequiredCount ?? 0)
        let pendingReviewCount = aggregate?.pendingReview.actionRequiredCount
            ?? sectionItemCount("approvals", from: home)
            ?? 0

        switch role {
        case .child:
            return [
                gate(
                    .todayTasks,
                    state: hasHomeSignal("today", homeSectionIds, homeMetricIds) || roleVisibility?.canSeeTodayTasks == true ? .visible : .gated,
                    detail: "只显示自己的今日任务。"
                ),
                gate(
                    .schoolHomework,
                    state: hasHomeSignal("homework", homeSectionIds, homeMetricIds) || roleVisibility?.canSeeSchoolHomework == true ? .visible : .gated,
                    detail: "作业入口只给引导和提交状态。"
                ),
                gate(
                    .growthPack,
                    state: hasHomeSignal("growth-pack-entitlements", homeSectionIds, homeMetricIds) || roleVisibility?.canSeeGrowthPack == true ? .visible : .gated,
                    detail: growthInstallAttention > 0 ? "等待家长确认成长包后继续挑战。" : "可继续运行已开放的成长包。"
                ),
                gate(
                    .creditReward,
                    state: .gated,
                    detail: "奖励兑换需要家长确认。"
                ),
                gate(
                    .deviceAccess,
                    state: .gated,
                    detail: "设备解锁只能由家长流程确认。"
                )
            ]
        case .guardian:
            return [
                gate(
                    .todayTasks,
                    state: .visible,
                    detail: "可查看孩子今日安排。"
                ),
                gate(
                    .growthPackInstall,
                    state: growthInstallAttention > 0 ? .gated : .visible,
                    detail: growthInstallAttention > 0 ? "\(growthInstallAttention) 个成长包需要复核。" : "成长包安装状态正常。",
                    actionRequired: growthInstallAttention > 0
                ),
                gate(
                    .schoolHomework,
                    state: pendingReviewCount > 0 ? .gated : .visible,
                    detail: pendingReviewCount > 0 ? "\(pendingReviewCount) 个学校/成长事项待处理。" : "学校作业验证状态正常。",
                    actionRequired: pendingReviewCount > 0
                ),
                gate(
                    .creditReward,
                    state: .visible,
                    detail: "成长积分发放和奖励开启仍走专属审批流程。"
                ),
                gate(
                    .offlineSync,
                    state: offlineConflicts > 0 ? .blocked : .visible,
                    detail: offlineConflicts > 0 ? "\(offlineConflicts) 个离线冲突需先处理。" : "离线同步没有阻断。",
                    actionRequired: offlineConflicts > 0
                )
            ]
        case .relative:
            return [
                gate(
                    .familyAchievement,
                    state: .visible,
                    detail: "只读查看家长开放的成长亮点。"
                ),
                gate(
                    .growthPackInstall,
                    state: .hidden,
                    detail: "成长包安装和权益信息不对亲友开放。"
                ),
                gate(
                    .creditReward,
                    state: .hidden,
                    detail: "亲友不能发成长积分或解锁设备。"
                )
            ]
        case .teacher:
            return [
                gate(
                    .schoolHomework,
                    state: .visible,
                    detail: "只显示学校作业验证上下文。"
                ),
                gate(
                    .aiHomework,
                    state: .gated,
                    detail: "AI 作业助手只提供引导过程摘要。"
                ),
                gate(
                    .growthPackInstall,
                    state: .hidden,
                    detail: "成长包购买和权益信息不对老师开放。"
                ),
                gate(
                    .creditReward,
                    state: .hidden,
                    detail: "成长积分发放由家庭和学校验证链路处理。"
                )
            ]
        }
    }

    private func moduleReadModels(
        for role: MobilePlatformPermissionGatewayViewerRole,
        gates: [MobilePlatformPermissionGate],
        home: MobileHomeViewModel?,
        aggregate: MobilePlatformAggregateSnapshot?
    ) -> [MobilePlatformPermissionGatewayModuleReadModel] {
        let gateByKind = Dictionary(uniqueKeysWithValues: gates.map { ($0.kind, $0) })
        let growthGate = gateByKind[.growthPackInstall] ?? gateByKind[.growthPack]
        let schoolGate = gateByKind[.schoolHomework]
        let aiGate = gateByKind[.aiHomework] ?? schoolGate
        let creditGate = gateByKind[.creditReward]
        let offlineGate = gateByKind[.offlineSync]
        let deviceGate = gateByKind[.deviceAccess]
        let growthInstallAttention = aggregate?.growthPackInstall.needsGuardianAttentionCount
            ?? metricValue("growth-pack-entitlements", from: home)
            ?? 0
        let pendingReviewCount = aggregate?.pendingReview.actionRequiredCount
            ?? sectionItemCount("approvals", from: home)
            ?? 0
        let offlineConflicts = (aggregate?.offlineSync.conflictCount ?? 0) + (aggregate?.offlineSync.rollbackRequiredCount ?? 0)

        return [
            module(
                .growthPackInstall,
                role: role,
                gate: growthGate,
                defaultGateState: growthInstallAttention > 0 ? .gated : .visible,
                sourceModule: .growthPackInstallEntitlement,
                actionRequired: growthInstallAttention > 0
            ),
            module(
                .marketplaceEntitlement,
                role: role,
                gate: growthGate,
                defaultGateState: growthInstallAttention > 0 ? .gated : .visible,
                sourceModule: .marketplaceEntitlementLifecycle,
                actionRequired: growthInstallAttention > 0
            ),
            module(
                .aiHomeworkReview,
                role: role,
                gate: aiGate,
                defaultGateState: pendingReviewCount > 0 ? .gated : .visible,
                sourceModule: .aiHomeworkManualReview,
                actionRequired: pendingReviewCount > 0
            ),
            module(
                .schoolLmsBoundary,
                role: role,
                gate: schoolGate,
                defaultGateState: pendingReviewCount > 0 ? .gated : .visible,
                sourceModule: .schoolLmsBoundary,
                actionRequired: pendingReviewCount > 0
            ),
            module(
                .creditConsentReconciliation,
                role: role,
                gate: creditGate,
                defaultGateState: .gated,
                sourceModule: .creditConsentReconciliation,
                actionRequired: false
            ),
            module(
                .offlineStatus,
                role: role,
                gate: offlineGate,
                defaultGateState: offlineConflicts > 0 ? .blocked : .visible,
                sourceModule: .mobileRoleBoundary,
                actionRequired: offlineConflicts > 0
            ),
            module(
                .deviceControl,
                role: role,
                gate: deviceGate,
                defaultGateState: role == .child ? .gated : .visible,
                sourceModule: .mobileRoleBoundary,
                actionRequired: role == .child
            ),
            module(
                .operationsReview,
                role: role,
                gate: nil,
                defaultGateState: offlineConflicts > 0 ? .gated : .hidden,
                sourceModule: .eventContracts,
                actionRequired: offlineConflicts > 0
            )
        ]
    }

    private func module(
        _ key: MobilePlatformPermissionGatewayModuleKey,
        role: MobilePlatformPermissionGatewayViewerRole,
        gate: MobilePlatformPermissionGate?,
        defaultGateState: MobilePlatformPermissionGateState,
        sourceModule: MobilePlatformPermissionGatewaySourceModule,
        actionRequired: Bool
    ) -> MobilePlatformPermissionGatewayModuleReadModel {
        let policy = key.rolePolicy
        let gateState = gate?.state ?? defaultGateState
        let visibility = visibility(
            for: key,
            role: role,
            gateState: gateState,
            allowedForCurrentRole: policy.visibleRoles.contains(role),
            actionRequired: actionRequired
        )
        let blockerCodes = blockerCodes(for: key, visibility: visibility, actionRequired: actionRequired)

        return MobilePlatformPermissionGatewayModuleReadModel(
            module: key,
            modulePublicRef: "mpg-\(key.rawValue)",
            sourceModule: sourceModule,
            visibility: visibility,
            canOpen: visibility == .visible,
            blockerCodes: blockerCodes,
            nextAction: nextAction(for: visibility),
            visibleToChild: policy.visibleRoles.contains(.child),
            visibleToGuardian: policy.visibleRoles.contains(.guardian),
            visibleToTeacher: policy.visibleRoles.contains(.teacher),
            visibleToRelative: policy.visibleRoles.contains(.relative),
            visibleToOperations: policy.visibleToOperations,
            showsOrder: false,
            showsEntitlementDetail: false,
            showsProviderOrModel: false,
            showsConsentDetail: false,
            showsCreditAmount: false,
            showsRawTranscript: false,
            showsTeacherPrivateNote: false,
            showsCrossChildContent: false,
            writesEntitlement: false,
            writesLedger: false,
            unlocksDevice: false,
            callsLms: false,
            callsAiProvider: false,
            sendsNotification: false
        )
    }

    private func visibility(
        for key: MobilePlatformPermissionGatewayModuleKey,
        role: MobilePlatformPermissionGatewayViewerRole,
        gateState: MobilePlatformPermissionGateState,
        allowedForCurrentRole: Bool,
        actionRequired: Bool
    ) -> MobilePlatformPermissionGatewayVisibility {
        guard allowedForCurrentRole else { return .hidden }
        if key == .operationsReview {
            return actionRequired ? .needsOperations : .hidden
        }

        switch gateState {
        case .visible:
            return actionRequired ? gatedVisibility(for: key, role: role) : .visible
        case .gated:
            return gatedVisibility(for: key, role: role)
        case .hidden:
            return .hidden
        case .blocked:
            return .blocked
        }
    }

    private func gatedVisibility(
        for key: MobilePlatformPermissionGatewayModuleKey,
        role: MobilePlatformPermissionGatewayViewerRole
    ) -> MobilePlatformPermissionGatewayVisibility {
        if key == .schoolLmsBoundary || key == .aiHomeworkReview {
            return role == .teacher ? .needsTeacher : .needsGuardian
        }
        if key == .operationsReview { return .needsOperations }
        return .needsGuardian
    }

    private func blockerCodes(
        for key: MobilePlatformPermissionGatewayModuleKey,
        visibility: MobilePlatformPermissionGatewayVisibility,
        actionRequired: Bool
    ) -> [MobilePlatformPermissionGatewayFindingCode] {
        switch visibility {
        case .visible:
            return actionRequired ? [key.defaultFindingCode] : []
        case .hidden:
            return [.viewerRoleHidden]
        case .needsGuardian, .needsTeacher, .needsOperations:
            return [key.defaultFindingCode]
        case .blocked:
            return [key.blockerFindingCode]
        }
    }

    private func moduleFindings(
        _ modules: [MobilePlatformPermissionGatewayModuleReadModel]
    ) -> [MobilePlatformPermissionGatewayFinding] {
        let findings = modules.flatMap { module in
            module.blockerCodes.map { code in
                MobilePlatformPermissionGatewayFinding(
                    code: code,
                    severity: severity(for: code, module: module),
                    message: code.safeMessage,
                    path: "modules.\(module.module.rawValue)",
                    module: module.module
                )
            }
        }
        return findings.isEmpty ? [
            MobilePlatformPermissionGatewayFinding(
                code: .ok,
                severity: .ok,
                message: MobilePlatformPermissionGatewayFindingCode.ok.safeMessage,
                path: "modules",
                module: nil
            )
        ] : findings
    }

    private func severity(
        for code: MobilePlatformPermissionGatewayFindingCode,
        module: MobilePlatformPermissionGatewayModuleReadModel
    ) -> MobilePlatformPermissionGatewayFindingSeverity {
        if code == .ok { return .ok }
        if module.visibility == .blocked || code == .unsafePayloadBlocked || code == .realSideEffectBlocked {
            return .blocker
        }
        if module.visibility == .hidden {
            return .info
        }
        return .warning
    }

    private func nextActions(
        from modules: [MobilePlatformPermissionGatewayModuleReadModel]
    ) -> [MobilePlatformPermissionGatewayNextAction] {
        modules
            .filter { $0.visibility != .hidden && $0.nextAction != .open }
            .map { module in
                MobilePlatformPermissionGatewayNextAction(
                    publicActionRef: "mpg-action-\(module.module.rawValue)",
                    module: module.module,
                    action: module.nextAction,
                    title: module.nextAction.title,
                    visibleToViewer: true,
                    writesSystem: false,
                    sendsNotification: false
                )
            }
    }

    private func nextAction(
        for visibility: MobilePlatformPermissionGatewayVisibility
    ) -> MobilePlatformPermissionGatewayNextActionKind {
        switch visibility {
        case .visible:
            return .open
        case .hidden:
            return .blocked
        case .needsGuardian:
            return .askGuardian
        case .needsTeacher:
            return .askTeacher
        case .needsOperations:
            return .askOperations
        case .blocked:
            return .blocked
        }
    }

    private func readModelState(
        _ modules: [MobilePlatformPermissionGatewayModuleReadModel]
    ) -> MobilePlatformPermissionGatewayReadModelState {
        if modules.contains(where: { $0.visibility == .blocked }) { return .blocked }
        if modules.contains(where: { [.needsGuardian, .needsTeacher, .needsOperations].contains($0.visibility) }) {
            return .gated
        }
        return .ready
    }

    private func isOffline(
        home: MobileHomeViewModel?,
        aggregate: MobilePlatformAggregateSnapshot?
    ) -> Bool {
        let offlineConflicts = (aggregate?.offlineSync.conflictCount ?? 0) + (aggregate?.offlineSync.rollbackRequiredCount ?? 0)
        return offlineConflicts > 0 || home?.sections.contains { $0.id == "offline" } == true
    }

    private func gate(
        _ kind: MobilePlatformPermissionGateKind,
        state: MobilePlatformPermissionGateState,
        detail: String,
        actionRequired: Bool = false
    ) -> MobilePlatformPermissionGate {
        MobilePlatformPermissionGate(
            kind: kind,
            state: state,
            title: kind.title,
            detail: detail,
            actionRequired: actionRequired,
            reasonCode: "\(kind.rawValue)_\(state.rawValue)"
        )
    }

    private func generatedAt(from aggregate: MobilePlatformAggregateSnapshot?) -> String {
        aggregate?.generatedAt.isEmpty == false ? aggregate?.generatedAt ?? "2026-06-24T09:00:00Z" : "2026-06-24T09:00:00Z"
    }

    private func hasHomeSignal(_ id: String, _ sectionIds: Set<String>, _ metricIds: Set<String>) -> Bool {
        sectionIds.contains(id) || metricIds.contains(id)
    }

    private func metricValue(_ id: String, from home: MobileHomeViewModel?) -> Int? {
        guard let value = home?.metrics.first(where: { $0.id == id })?.value else { return nil }
        return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func sectionItemCount(_ id: String, from home: MobileHomeViewModel?) -> Int? {
        home?.sections.first { $0.id == id }?.items.count
    }

    private func tone(for state: MobilePlatformPermissionGateState) -> MobileHomeTone {
        switch state {
        case .visible:
            return .positive
        case .gated:
            return .attention
        case .hidden:
            return .neutral
        case .blocked:
            return .risk
        }
    }

    private func tone(for visibility: MobilePlatformPermissionGatewayVisibility) -> MobileHomeTone {
        switch visibility {
        case .visible:
            return .positive
        case .needsGuardian, .needsTeacher, .needsOperations:
            return .attention
        case .hidden:
            return .neutral
        case .blocked:
            return .risk
        }
    }

    private func icon(
        for kind: MobilePlatformPermissionGateKind,
        state: MobilePlatformPermissionGateState
    ) -> String {
        if state == .hidden { return "eye.slash" }
        if state == .blocked { return "xmark.octagon" }
        switch kind {
        case .todayTasks:
            return "checklist"
        case .growthPack:
            return "shippingbox"
        case .growthPackInstall:
            return "square.and.arrow.down"
        case .schoolHomework:
            return "graduationcap"
        case .aiHomework:
            return "brain.head.profile"
        case .creditReward:
            return "star.circle"
        case .familyAchievement:
            return "rosette"
        case .offlineSync:
            return "arrow.triangle.2.circlepath"
        case .deviceAccess:
            return "lock.shield"
        }
    }

    private func icon(
        for module: MobilePlatformPermissionGatewayModuleKey,
        visibility: MobilePlatformPermissionGatewayVisibility
    ) -> String {
        if visibility == .hidden { return "eye.slash" }
        if visibility == .blocked { return "xmark.octagon" }
        switch module {
        case .growthPackInstall:
            return "square.and.arrow.down"
        case .marketplaceEntitlement:
            return "cart"
        case .aiHomeworkReview:
            return "brain.head.profile"
        case .schoolLmsBoundary:
            return "graduationcap"
        case .creditConsentReconciliation:
            return "star.circle"
        case .offlineStatus:
            return "arrow.triangle.2.circlepath"
        case .deviceControl:
            return "lock.shield"
        case .operationsReview:
            return "wrench.and.screwdriver"
        }
    }

    private func containsUnsafePayload(_ values: [String]) -> Bool {
        if MobileSyncPayloadGuard.isUnsafe(values) { return true }
        let probe = MobilePlatformPermissionGatewaySnapshot(
            generatedAt: "",
            viewerRole: .guardian,
            gates: values.map {
                MobilePlatformPermissionGate(
                    kind: .deviceAccess,
                    state: .blocked,
                    title: $0,
                    detail: $0,
                    actionRequired: false,
                    reasonCode: $0
                )
            },
            publicSummary: .empty,
            sideEffects: sideEffects
        )
        return !Self.redacts(probe)
    }

    private func safeBlockedSnapshot(
        viewerRole: MobilePlatformPermissionGatewayViewerRole
    ) -> MobilePlatformPermissionGatewaySnapshot {
        let gates = [
            MobilePlatformPermissionGate(
                kind: .deviceAccess,
                state: .blocked,
                title: "权限闸门",
                detail: "检测到不安全展示内容，已切换为本地安全保护视图。",
                actionRequired: viewerRole == .guardian,
                reasonCode: "unsafe_payload_blocked"
            )
        ]
        return MobilePlatformPermissionGatewaySnapshot(
            generatedAt: "2026-06-24T09:00:00Z",
            viewerRole: viewerRole,
            gates: gates,
            publicSummary: MobilePlatformPermissionGatewayPublicSummary(gates: gates),
            sideEffects: sideEffects
        )
    }

    private func safeBlockedReadModel(
        viewerRole: MobilePlatformPermissionGatewayViewerRole,
        platform: MobilePlatformPermissionGatewayPlatform
    ) -> MobilePlatformPermissionGatewayReadModelReport {
        let module = MobilePlatformPermissionGatewayModuleReadModel(
            module: .deviceControl,
            modulePublicRef: "mpg-device_control",
            sourceModule: .mobileRoleBoundary,
            visibility: .blocked,
            canOpen: false,
            blockerCodes: [.unsafePayloadBlocked],
            nextAction: .blocked,
            visibleToChild: true,
            visibleToGuardian: true,
            visibleToTeacher: false,
            visibleToRelative: false,
            visibleToOperations: true,
            showsOrder: false,
            showsEntitlementDetail: false,
            showsProviderOrModel: false,
            showsConsentDetail: false,
            showsCreditAmount: false,
            showsRawTranscript: false,
            showsTeacherPrivateNote: false,
            showsCrossChildContent: false,
            writesEntitlement: false,
            writesLedger: false,
            unlocksDevice: false,
            callsLms: false,
            callsAiProvider: false,
            sendsNotification: false
        )
        let finding = MobilePlatformPermissionGatewayFinding(
            code: .unsafePayloadBlocked,
            severity: .blocker,
            message: MobilePlatformPermissionGatewayFindingCode.unsafePayloadBlocked.safeMessage,
            path: "modules.device_control",
            module: .deviceControl
        )
        return MobilePlatformPermissionGatewayReadModelReport(
            accepted: false,
            generatedAt: "2026-06-24T09:00:00Z",
            state: .blocked,
            viewer: MobilePlatformPermissionGatewayViewerReadModel(
                actorPublicRef: "viewer-\(viewerRole.rawValue)",
                childPublicRef: viewerRole == .child ? "child-current" : nil,
                role: viewerRole,
                platform: platform,
                offline: false,
                authorizedChildCount: viewerRole == .child ? 1 : 0
            ),
            modules: [module],
            findings: [finding],
            nextActions: [
                MobilePlatformPermissionGatewayNextAction(
                    publicActionRef: "mpg-action-device_control",
                    module: .deviceControl,
                    action: .blocked,
                    title: MobilePlatformPermissionGatewayNextActionKind.blocked.title,
                    visibleToViewer: true,
                    writesSystem: false,
                    sendsNotification: false
                )
            ],
            publicSummary: MobilePlatformPermissionGatewayReadModelPublicSummary(
                generatedAt: "2026-06-24T09:00:00Z",
                gatewayPublicRef: "mpg-gateway",
                viewerPublicRef: "viewer-\(viewerRole.rawValue)",
                childPublicRef: viewerRole == .child ? "child-current" : nil,
                familyPublicRef: "family-current",
                state: .blocked,
                viewerRole: viewerRole,
                platform: platform,
                modules: [module],
                findingCodes: [.unsafePayloadBlocked]
            ),
            sideEffects: MobilePlatformPermissionGatewayReadModelSideEffects()
        )
    }
}

enum MobilePlatformPermissionGatewayViewerRole: String, CaseIterable, Equatable {
    case child
    case guardian
    case relative
    case teacher
}

enum MobilePlatformPermissionGatewayPlatform: String, CaseIterable, Equatable {
    case ios
    case android
    case cloud
}

enum MobilePlatformPermissionGatewayReadModelState: String, Equatable {
    case ready
    case gated
    case blocked
}

enum MobilePlatformPermissionGatewayModuleKey: String, CaseIterable, Equatable {
    case growthPackInstall = "growth_pack_install"
    case marketplaceEntitlement = "marketplace_entitlement"
    case aiHomeworkReview = "ai_homework_review"
    case schoolLmsBoundary = "school_lms_boundary"
    case creditConsentReconciliation = "credit_consent_reconciliation"
    case offlineStatus = "offline_status"
    case deviceControl = "device_control"
    case operationsReview = "operations_review"

    var title: String {
        switch self {
        case .growthPackInstall:
            return "成长包安装"
        case .marketplaceEntitlement:
            return "市场权益"
        case .aiHomeworkReview:
            return "AI 作业复核"
        case .schoolLmsBoundary:
            return "学校 LMS 边界"
        case .creditConsentReconciliation:
            return "成长积分同意核对"
        case .offlineStatus:
            return "离线状态"
        case .deviceControl:
            return "设备控制"
        case .operationsReview:
            return "运营复核"
        }
    }

    fileprivate var rolePolicy: MobilePlatformPermissionGatewayRolePolicy {
        switch self {
        case .growthPackInstall:
            return MobilePlatformPermissionGatewayRolePolicy(visibleRoles: [.child, .guardian], visibleToOperations: true)
        case .marketplaceEntitlement:
            return MobilePlatformPermissionGatewayRolePolicy(visibleRoles: [.guardian], visibleToOperations: true)
        case .aiHomeworkReview:
            return MobilePlatformPermissionGatewayRolePolicy(visibleRoles: [.child, .guardian, .teacher], visibleToOperations: true)
        case .schoolLmsBoundary:
            return MobilePlatformPermissionGatewayRolePolicy(visibleRoles: [.child, .guardian, .teacher], visibleToOperations: true)
        case .creditConsentReconciliation:
            return MobilePlatformPermissionGatewayRolePolicy(visibleRoles: [.guardian], visibleToOperations: true)
        case .offlineStatus:
            return MobilePlatformPermissionGatewayRolePolicy(visibleRoles: [.child, .guardian], visibleToOperations: true)
        case .deviceControl:
            return MobilePlatformPermissionGatewayRolePolicy(visibleRoles: [.child, .guardian], visibleToOperations: true)
        case .operationsReview:
            return MobilePlatformPermissionGatewayRolePolicy(visibleRoles: [], visibleToOperations: true)
        }
    }

    fileprivate var defaultFindingCode: MobilePlatformPermissionGatewayFindingCode {
        switch self {
        case .growthPackInstall:
            return .installEntitlementBlocked
        case .marketplaceEntitlement:
            return .marketplaceEntitlementBlocked
        case .aiHomeworkReview:
            return .aiHomeworkReviewBlocked
        case .schoolLmsBoundary:
            return .schoolLmsBoundaryBlocked
        case .creditConsentReconciliation:
            return .consentPolicyGated
        case .offlineStatus:
            return .offlineUnsupported
        case .deviceControl:
            return .mobileRoleDecisionBlocked
        case .operationsReview:
            return .viewerRoleHidden
        }
    }

    fileprivate var blockerFindingCode: MobilePlatformPermissionGatewayFindingCode {
        switch self {
        case .creditConsentReconciliation:
            return .creditConsentReconciliationBlocked
        case .offlineStatus:
            return .offlineUnsupported
        default:
            return defaultFindingCode
        }
    }
}

fileprivate struct MobilePlatformPermissionGatewayRolePolicy {
    var visibleRoles: Set<MobilePlatformPermissionGatewayViewerRole>
    var visibleToOperations: Bool
}

enum MobilePlatformPermissionGatewayVisibility: String, Equatable {
    case visible
    case hidden
    case needsGuardian = "needs_guardian"
    case needsTeacher = "needs_teacher"
    case needsOperations = "needs_operations"
    case blocked

    var label: String {
        switch self {
        case .visible:
            return "可见"
        case .hidden:
            return "已隐藏"
        case .needsGuardian:
            return "需家长"
        case .needsTeacher:
            return "需老师"
        case .needsOperations:
            return "需运营"
        case .blocked:
            return "已阻断"
        }
    }

    var detail: String {
        switch self {
        case .visible:
            return "只读可打开，不会触发写入。"
        case .hidden:
            return "当前角色不可见。"
        case .needsGuardian:
            return "需要家长在专属流程中确认。"
        case .needsTeacher:
            return "需要老师在学校流程中确认。"
        case .needsOperations:
            return "需要运营在后台流程中复核。"
        case .blocked:
            return "安全闸门已阻断。"
        }
    }
}

enum MobilePlatformPermissionGatewaySourceModule: String, Equatable {
    case growthPackInstallEntitlement = "growth_pack_install_entitlement"
    case marketplaceEntitlementLifecycle = "marketplace_entitlement_lifecycle"
    case aiHomeworkManualReview = "ai_homework_manual_review"
    case schoolLmsBoundary = "school_lms_boundary"
    case creditConsentReconciliation = "credit_consent_reconciliation"
    case mobileRoleBoundary = "mobile_role_boundary"
    case eventContracts = "event_contracts"
    case privacySafety = "privacy_safety"
}

enum MobilePlatformPermissionGatewayFindingSeverity: String, Equatable {
    case ok
    case info
    case warning
    case blocker
}

enum MobilePlatformPermissionGatewayFindingCode: String, Equatable {
    case ok = "MOBILE_PERMISSION_GATEWAY_READ_MODEL_OK"
    case viewerScopeBlocked = "VIEWER_SCOPE_BLOCKED"
    case viewerRoleHidden = "VIEWER_ROLE_HIDDEN"
    case mobileRoleDecisionBlocked = "MOBILE_ROLE_DECISION_BLOCKED"
    case installEntitlementBlocked = "INSTALL_ENTITLEMENT_BLOCKED"
    case marketplaceEntitlementBlocked = "MARKETPLACE_ENTITLEMENT_BLOCKED"
    case aiHomeworkReviewBlocked = "AI_HOMEWORK_REVIEW_BLOCKED"
    case schoolLmsBoundaryBlocked = "SCHOOL_LMS_BOUNDARY_BLOCKED"
    case consentPolicyBlocked = "CONSENT_POLICY_BLOCKED"
    case consentPolicyGated = "CONSENT_POLICY_GATED"
    case creditConsentReconciliationBlocked = "CREDIT_CONSENT_RECONCILIATION_BLOCKED"
    case offlineUnsupported = "OFFLINE_UNSUPPORTED"
    case privacyLinkMissing = "PRIVACY_LINK_MISSING"
    case eventEvidenceMissing = "EVENT_EVIDENCE_MISSING"
    case eventPayloadLeak = "EVENT_PAYLOAD_LEAK"
    case roleVisibilityLeak = "ROLE_VISIBILITY_LEAK"
    case publicSummaryLeak = "PUBLIC_SUMMARY_LEAK"
    case realSideEffectBlocked = "REAL_SIDE_EFFECT_BLOCKED"
    case unsafePayloadBlocked = "UNSAFE_PAYLOAD_BLOCKED"

    var safeMessage: String {
        switch self {
        case .ok:
            return "只读权限模型通过。"
        case .viewerRoleHidden:
            return "当前角色只能看到安全范围。"
        case .viewerScopeBlocked:
            return "访问范围不匹配。"
        case .mobileRoleDecisionBlocked:
            return "移动角色策略需要确认。"
        case .installEntitlementBlocked:
            return "成长包安装需要确认。"
        case .marketplaceEntitlementBlocked:
            return "市场权益需要确认。"
        case .aiHomeworkReviewBlocked:
            return "AI 作业复核仍在等待。"
        case .schoolLmsBoundaryBlocked:
            return "学校边界需要确认。"
        case .consentPolicyBlocked:
            return "家庭同意策略已阻断。"
        case .consentPolicyGated:
            return "家庭同意策略需要确认。"
        case .creditConsentReconciliationBlocked:
            return "成长积分同意核对已冻结。"
        case .offlineUnsupported:
            return "离线状态需要先处理。"
        case .privacyLinkMissing:
            return "隐私链路需要补齐。"
        case .eventEvidenceMissing:
            return "事件证据需要补齐。"
        case .eventPayloadLeak:
            return "事件摘要不应展示敏感内容。"
        case .roleVisibilityLeak:
            return "角色可见性需要收紧。"
        case .publicSummaryLeak:
            return "公开摘要需要脱敏。"
        case .realSideEffectBlocked:
            return "真实写操作已阻断。"
        case .unsafePayloadBlocked:
            return "不安全展示内容已阻断。"
        }
    }
}

enum MobilePlatformPermissionGatewayNextActionKind: String, Equatable {
    case open
    case askGuardian = "ask_guardian"
    case askTeacher = "ask_teacher"
    case askOperations = "ask_operations"
    case connectOnline = "connect_online"
    case blocked

    var title: String {
        switch self {
        case .open:
            return "打开只读模块"
        case .askGuardian:
            return "请家长确认"
        case .askTeacher:
            return "请老师确认"
        case .askOperations:
            return "请运营复核"
        case .connectOnline:
            return "联网后继续"
        case .blocked:
            return "保持阻断"
        }
    }
}

enum MobilePlatformPermissionGateKind: String, CaseIterable, Equatable {
    case todayTasks
    case growthPack
    case growthPackInstall
    case schoolHomework
    case aiHomework
    case creditReward
    case familyAchievement
    case offlineSync
    case deviceAccess

    var title: String {
        switch self {
        case .todayTasks:
            return "今日任务"
        case .growthPack:
            return "成长包运行"
        case .growthPackInstall:
            return "成长包安装"
        case .schoolHomework:
            return "学校作业"
        case .aiHomework:
            return "AI 作业引导"
        case .creditReward:
            return "成长积分与奖励"
        case .familyAchievement:
            return "家庭荣誉"
        case .offlineSync:
            return "离线同步"
        case .deviceAccess:
            return "设备访问"
        }
    }
}

enum MobilePlatformPermissionGateState: String, Equatable {
    case visible
    case gated
    case hidden
    case blocked

    var label: String {
        switch self {
        case .visible:
            return "可见"
        case .gated:
            return "需确认"
        case .hidden:
            return "已隐藏"
        case .blocked:
            return "已阻断"
        }
    }
}

struct MobilePlatformPermissionGate: Identifiable, Equatable {
    var kind: MobilePlatformPermissionGateKind
    var state: MobilePlatformPermissionGateState
    var title: String
    var detail: String
    var actionRequired: Bool
    var reasonCode: String

    var id: String { kind.rawValue }
}

struct MobilePlatformPermissionGatewayPublicSummary: Equatable {
    var visibleCount: Int
    var gatedCount: Int
    var hiddenCount: Int
    var blockedCount: Int
    var actionRequiredCount: Int
    var findingCodes: [String]

    static let empty = MobilePlatformPermissionGatewayPublicSummary(
        visibleCount: 0,
        gatedCount: 0,
        hiddenCount: 0,
        blockedCount: 0,
        actionRequiredCount: 0,
        findingCodes: []
    )

    init(gates: [MobilePlatformPermissionGate]) {
        visibleCount = gates.filter { $0.state == .visible }.count
        gatedCount = gates.filter { $0.state == .gated }.count
        hiddenCount = gates.filter { $0.state == .hidden }.count
        blockedCount = gates.filter { $0.state == .blocked }.count
        actionRequiredCount = gates.filter(\.actionRequired).count
        findingCodes = gates
            .filter { $0.state != .visible || $0.actionRequired }
            .map(\.reasonCode)
    }

    private init(
        visibleCount: Int,
        gatedCount: Int,
        hiddenCount: Int,
        blockedCount: Int,
        actionRequiredCount: Int,
        findingCodes: [String]
    ) {
        self.visibleCount = visibleCount
        self.gatedCount = gatedCount
        self.hiddenCount = hiddenCount
        self.blockedCount = blockedCount
        self.actionRequiredCount = actionRequiredCount
        self.findingCodes = findingCodes
    }
}

struct MobilePlatformPermissionGatewaySideEffects: Equatable {
    let callsFamilyControls = false
    let callsCloud = false
    let callsAi = false
    let callsSchoolSystem = false
    let chargesPayment = false
    let createsOrder = false
    let writesEntitlement = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false

    var hasTriggeredSideEffect: Bool {
        callsFamilyControls
            || callsCloud
            || callsAi
            || callsSchoolSystem
            || chargesPayment
            || createsOrder
            || writesEntitlement
            || writesLedger
            || grantsCredit
            || unlocksDevice
    }
}

struct MobilePlatformPermissionGatewaySnapshot: Equatable {
    var generatedAt: String
    var viewerRole: MobilePlatformPermissionGatewayViewerRole
    var gates: [MobilePlatformPermissionGate]
    var publicSummary: MobilePlatformPermissionGatewayPublicSummary
    var sideEffects: MobilePlatformPermissionGatewaySideEffects

    var displayValues: [String] {
        [generatedAt, viewerRole.rawValue]
            + gates.flatMap { [$0.kind.rawValue, $0.state.rawValue, $0.title, $0.detail, $0.reasonCode] }
            + publicSummary.findingCodes
    }
}

struct MobilePlatformPermissionGatewayModuleReadModel: Identifiable, Equatable {
    var module: MobilePlatformPermissionGatewayModuleKey
    var modulePublicRef: String
    var sourceModule: MobilePlatformPermissionGatewaySourceModule
    var visibility: MobilePlatformPermissionGatewayVisibility
    var canOpen: Bool
    var blockerCodes: [MobilePlatformPermissionGatewayFindingCode]
    var nextAction: MobilePlatformPermissionGatewayNextActionKind
    var visibleToChild: Bool
    var visibleToGuardian: Bool
    var visibleToTeacher: Bool
    var visibleToRelative: Bool
    var visibleToOperations: Bool
    var showsOrder: Bool
    var showsEntitlementDetail: Bool
    var showsProviderOrModel: Bool
    var showsConsentDetail: Bool
    var showsCreditAmount: Bool
    var showsRawTranscript: Bool
    var showsTeacherPrivateNote: Bool
    var showsCrossChildContent: Bool
    var writesEntitlement: Bool
    var writesLedger: Bool
    var unlocksDevice: Bool
    var callsLms: Bool
    var callsAiProvider: Bool
    var sendsNotification: Bool

    var id: String { module.rawValue }

    var displayValues: [String] {
        [
            module.rawValue,
            modulePublicRef,
            sourceModule.rawValue,
            visibility.rawValue,
            nextAction.rawValue
        ] + blockerCodes.map(\.rawValue)
    }
}

struct MobilePlatformPermissionGatewayViewerReadModel: Equatable {
    var actorPublicRef: String
    var childPublicRef: String?
    var role: MobilePlatformPermissionGatewayViewerRole
    var platform: MobilePlatformPermissionGatewayPlatform
    var offline: Bool
    var authorizedChildCount: Int

    var displayValues: [String] {
        [actorPublicRef, childPublicRef, role.rawValue, platform.rawValue].compactMap { $0 }
    }
}

struct MobilePlatformPermissionGatewayFinding: Equatable {
    var code: MobilePlatformPermissionGatewayFindingCode
    var severity: MobilePlatformPermissionGatewayFindingSeverity
    var message: String
    var path: String
    var module: MobilePlatformPermissionGatewayModuleKey?

    var displayValues: [String] {
        [code.rawValue, severity.rawValue, message, path, module?.rawValue].compactMap { $0 }
    }
}

struct MobilePlatformPermissionGatewayNextAction: Equatable {
    var publicActionRef: String
    var module: MobilePlatformPermissionGatewayModuleKey
    var action: MobilePlatformPermissionGatewayNextActionKind
    var title: String
    var visibleToViewer: Bool
    var writesSystem: Bool
    var sendsNotification: Bool

    var displayValues: [String] {
        [publicActionRef, module.rawValue, action.rawValue, title]
    }
}

struct MobilePlatformPermissionGatewayReadModelPublicSummary: Equatable {
    var generatedAt: String
    var gatewayPublicRef: String
    var viewerPublicRef: String
    var childPublicRef: String?
    var familyPublicRef: String
    var state: MobilePlatformPermissionGatewayReadModelState
    var viewerRole: MobilePlatformPermissionGatewayViewerRole
    var platform: MobilePlatformPermissionGatewayPlatform
    var visibleModuleCount: Int
    var blockedModuleCount: Int
    var gatedModuleCount: Int
    var findingCodes: [MobilePlatformPermissionGatewayFindingCode]
    let callsNetwork = false
    let callsAiProvider = false
    let callsLms = false
    let writesEntitlement = false
    let writesLedger = false
    let writesDatabase = false
    let unlocksDevice = false
    let sendsNotification = false

    init(
        generatedAt: String,
        gatewayPublicRef: String,
        viewerPublicRef: String,
        childPublicRef: String?,
        familyPublicRef: String,
        state: MobilePlatformPermissionGatewayReadModelState,
        viewerRole: MobilePlatformPermissionGatewayViewerRole,
        platform: MobilePlatformPermissionGatewayPlatform,
        modules: [MobilePlatformPermissionGatewayModuleReadModel],
        findingCodes: [MobilePlatformPermissionGatewayFindingCode]
    ) {
        self.generatedAt = generatedAt
        self.gatewayPublicRef = gatewayPublicRef
        self.viewerPublicRef = viewerPublicRef
        self.childPublicRef = childPublicRef
        self.familyPublicRef = familyPublicRef
        self.state = state
        self.viewerRole = viewerRole
        self.platform = platform
        visibleModuleCount = modules.filter { $0.visibility == .visible }.count
        blockedModuleCount = modules.filter { $0.visibility == .blocked }.count
        gatedModuleCount = modules.filter { [.needsGuardian, .needsTeacher, .needsOperations].contains($0.visibility) }.count
        self.findingCodes = findingCodes
    }

    var displayValues: [String] {
        [
            generatedAt,
            gatewayPublicRef,
            viewerPublicRef,
            childPublicRef,
            familyPublicRef,
            state.rawValue,
            viewerRole.rawValue,
            platform.rawValue
        ].compactMap { $0 } + findingCodes.map(\.rawValue)
    }
}

struct MobilePlatformPermissionGatewayReadModelSideEffects: Equatable {
    let callsNetwork = false
    let callsAiProvider = false
    let callsLocalModel = false
    let callsLms = false
    let callsAppStore = false
    let callsDevicePolicyRuntime = false
    let writesEntitlement = false
    let writesLedger = false
    let writesDatabase = false
    let writesQueue = false
    let unlocksDevice = false
    let sendsNotification = false
    let writesSchoolSystem = false

    var hasTriggeredSideEffect: Bool {
        callsNetwork
            || callsAiProvider
            || callsLocalModel
            || callsLms
            || callsAppStore
            || callsDevicePolicyRuntime
            || writesEntitlement
            || writesLedger
            || writesDatabase
            || writesQueue
            || unlocksDevice
            || sendsNotification
            || writesSchoolSystem
    }
}

struct MobilePlatformPermissionGatewayReadModelReport: Equatable {
    var accepted: Bool
    var generatedAt: String
    var state: MobilePlatformPermissionGatewayReadModelState
    var viewer: MobilePlatformPermissionGatewayViewerReadModel
    var modules: [MobilePlatformPermissionGatewayModuleReadModel]
    var findings: [MobilePlatformPermissionGatewayFinding]
    var nextActions: [MobilePlatformPermissionGatewayNextAction]
    var publicSummary: MobilePlatformPermissionGatewayReadModelPublicSummary
    var sideEffects: MobilePlatformPermissionGatewayReadModelSideEffects

    var displayValues: [String] {
        [generatedAt, state.rawValue]
            + viewer.displayValues
            + modules.flatMap(\.displayValues)
            + findings.flatMap(\.displayValues)
            + nextActions.flatMap(\.displayValues)
            + publicSummary.displayValues
    }
}
