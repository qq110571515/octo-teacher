import Foundation

/// 监护人与孩子同意策略的本地确定性投影器。
///
/// 给定一条同意用例（用途、年龄段、同意/assent 状态、身份归属、亲友/老师授权、
/// 脱敏与撤回/导出删除审计状态），产出按角色脱敏的只读快照与关键阻断发现。
/// 不接任何外部系统，所有判断都是纯函数。
struct GuardianChildConsentPolicyBuilder {
    var generatedAt = "2026-06-24T12:00:00Z"
    var redactionSalt = "guardian-child-consent-policy-ios-v1"

    // swiftlint:disable:next function_body_length
    func build(
        viewerRole: GuardianChildConsentPolicyViewerRole,
        purpose: GuardianChildConsentPolicyPurpose,
        ageBand: GuardianChildConsentAgeBand = .age13To15,
        guardianConsent: GuardianChildConsentState = .granted,
        childAssent: GuardianChildConsentState = .granted,
        sameFamily: Bool = true,
        linkedChild: Bool = true,
        relativeAuthorized: Bool = true,
        teacherAuthorized: Bool = true,
        verifiedSchoolRoster: Bool = true,
        publicCopyRedacted: Bool = true,
        exportRequested: Bool = false,
        deleteRequested: Bool = false,
        exportDeleteAuditLinked: Bool = true,
        revocationRequired: Bool = false,
        revocationPropagated: Bool = true,
        requiresManualReview: Bool = false,
        inputRisk: GuardianChildConsentPolicyInputRisk = .safe
    ) -> GuardianChildConsentPolicySnapshot {
        let visibility = visibility(for: viewerRole)

        // 不安全负载 / endpoint：直接阻断，不把任何原始内容带入快照。
        if inputRisk.blocksPolicy {
            return blockedSnapshot(
                viewerRole: viewerRole,
                visibility: visibility,
                purpose: purpose,
                ageBand: ageBand,
                code: .unsafePayloadBlocked,
                message: "检测到不安全负载或 endpoint，已在进入策略前阻断。"
            )
        }

        // 1. 跨孩子 / 跨家庭错挂。
        let identityMismatch = !sameFamily || !linkedChild
        // 2. 缺家长同意（pending / denied）。
        let guardianMissing = guardianConsent == .pending || guardianConsent == .denied
        // 3. 同意过期 / 撤回。
        let guardianExpiredOrRevoked = guardianConsent == .expired || guardianConsent == .revoked
        // 4. 孩子年龄段需要 assent 但缺失。
        let assentRequired = ageBand.requiresChildAssent && purpose != .dataExportDelete
        let assentMissing = assentRequired && childAssent != .granted
        // 5. 目的错配：公开分享但年龄段不允许；公开 / 学校用途缺前置同意。
        let agePublicBlocked = purpose.isPublicFacing && !ageBand.allowsPublicShare
        // 6. 公开分享未脱敏。
        let publicNotRedacted = purpose.isPublicFacing && !publicCopyRedacted
        // 7. 撤回未传播。
        let revocationNotPropagated = revocationRequired && !revocationPropagated
        // 8. 导出 / 删除缺审计。
        let exportDeleteActive = purpose == .dataExportDelete && (exportRequested || deleteRequested)
        let exportDeleteAuditMissing = exportDeleteActive && !exportDeleteAuditLinked
        // 9. 亲友越权：亲友看非亲友用途或未被授权。
        let relativeScopeExceeded = viewerRole == .relative && (!purpose.isRelativeFacing || !relativeAuthorized)
        // 10. 老师越权：老师看非学校用途，或学校名单未核验。
        let teacherScopeExceeded = viewerRole == .teacher && (!purpose.isSchoolFacing || !teacherAuthorized || !verifiedSchoolRoster)

        var blockerFlags: [(Bool, GuardianChildConsentPolicyFindingCode, String, String)] = [
            (identityMismatch, .crossChildFamilyMismatch, "同意被错挂到其它孩子或其它家庭，已阻断。", "identity"),
            (guardianMissing, .guardianConsentRequired, "缺少有效家长同意，无法放行该用途。", "guardian"),
            (guardianExpiredOrRevoked, .consentExpiredOrRevoked, "家长同意已过期或被撤回，需要重新授权。", "guardian.lifecycle"),
            (assentMissing, .childAssentRequired, "该年龄段需要孩子 assent（共同同意），目前缺失。", "assent"),
            (agePublicBlocked, .agePublicShareBlocked, "当前年龄段不允许公开分享。", "age.public"),
            (publicNotRedacted, .publicShareNotRedacted, "公开分享必须先完成脱敏审查。", "public.redaction"),
            (revocationNotPropagated, .revocationNotPropagated, "撤回尚未传播到全部下游，先暂停可见性。", "revocation"),
            (exportDeleteAuditMissing, .exportDeleteAuditMissing, "导出 / 删除请求缺少完整审计链。", "export.audit"),
            (relativeScopeExceeded, .relativeScopeExceeded, "亲友超出被授权范围，已阻断该内容。", "relative.scope"),
            (teacherScopeExceeded, .teacherScopeExceeded, "老师只能看学校相关授权，已阻断非学校内容。", "teacher.scope")
        ]
        blockerFlags.removeAll { !$0.0 }

        let hasBlocker = !blockerFlags.isEmpty
        let gated = !hasBlocker && (requiresManualReview || guardianConsent == .pending || (assentRequired && childAssent == .pending))
        let state: GuardianChildConsentPolicyState = hasBlocker ? .blocked : (gated ? .gated : .allowed)

        var findings: [GuardianChildConsentPolicyFinding] = blockerFlags.map { _, code, message, seed in
            finding(code, .blocker, message, seed)
        }

        // 角色可见性 info 发现。
        switch viewerRole {
        case .child:
            findings.append(finding(.childVisibilityRedacted, .info, "孩子端已隐藏家长内部原因、亲友权限明细和老师备注。", "visibility.child"))
        case .relative:
            findings.append(finding(.relativeBoundaryApplied, .info, "亲友只读，仅展示被授权范围内的脱敏摘要。", "visibility.relative"))
        case .teacher:
            findings.append(finding(.teacherBoundaryApplied, .info, "老师只看学校相关授权，家庭私密与亲友内容已隐藏。", "visibility.teacher"))
        case .publicViewer:
            findings.append(finding(.publicRedactionApplied, .info, "公开访客只看公开脱敏摘要，内部同意状态不可见。", "visibility.public"))
        case .guardian:
            break
        }

        if revocationRequired && revocationPropagated {
            findings.append(finding(.revocationPropagated, .ok, "撤回已传播到全部下游并暂停可见性。", "revocation.ok"))
        }
        if requiresManualReview && !hasBlocker {
            findings.append(finding(.purposeMismatch, .warning, "该用途需要家长人工复核后才放行。", "manual.review"))
        }
        if state == .allowed {
            findings.insert(finding(.policyReady, .ok, "同意策略本地投影就绪。", "policy"), at: 0)
        }
        findings.append(finding(.sideEffectFree, .ok, "本地只读投影：不写库、不发成长积分、不通知、不接 AI / 学校 / 设备。", "side-effect"))

        let decision = decision(
            state: state,
            purpose: purpose,
            viewerRole: viewerRole,
            guardianUsable: guardianConsent.isUsable,
            childAssent: childAssent,
            assentRequired: assentRequired,
            relativeAuthorized: relativeAuthorized,
            teacherAuthorized: teacherAuthorized,
            verifiedSchoolRoster: verifiedSchoolRoster,
            exportRequested: exportRequested,
            deleteRequested: deleteRequested,
            requiresManualReview: requiresManualReview
        )
        let revocationPlan = GuardianChildConsentRevocationPlan(
            revocationRequired: revocationRequired,
            revocationApplied: revocationRequired && revocationPropagated,
            deletionSuppressedVisibility: revocationRequired || deleteRequested,
            pendingTargetCount: revocationNotPropagated ? 2 : 0
        )
        let audit = GuardianChildConsentAuditSummary(
            linkedEventCount: hasBlocker ? 4 : 6,
            missingEventCount: exportDeleteAuditMissing ? 1 : 0
        )

        let summary = GuardianChildConsentPolicyPublicSummary(
            generatedAt: generatedAt,
            viewerRole: viewerRole,
            state: state,
            purpose: purpose,
            policyPublicRef: stableRef("pol", "\(purpose.rawValue):policy"),
            requestPublicRef: stableRef("req", "\(purpose.rawValue):\(ageBand.rawValue)"),
            familyPublicRef: stableRef("fam", "family-self"),
            childPublicRef: stableRef("kid", "child-self"),
            guardianPublicRef: stableRef("grd", "guardian-self"),
            findingCodes: findings.map(\.code),
            guardianConsentGranted: visibility.canSeeInternalConsentState && guardianConsent.isUsable,
            childAssentGranted: visibility.canSeeInternalConsentState && childAssent.isUsable,
            relativeVisible: decision.relativeVisible,
            schoolVisible: decision.schoolVisible,
            publicVisible: decision.publicVisible,
            exportAllowed: decision.exportAllowed,
            deleteAllowed: decision.deleteAllowed,
            revocationApplied: revocationPlan.revocationApplied
        )

        let snapshot = GuardianChildConsentPolicySnapshot(
            generatedAt: generatedAt,
            state: state,
            purpose: purpose,
            ageBand: ageBand,
            headline: headline(state: state, purpose: purpose, viewerRole: viewerRole),
            childSafeCopy: childCopy(state: state),
            audienceNote: viewerRole.audienceNote,
            visibility: visibility,
            guardianConsentDisplay: consentDisplay(guardianConsent, kind: .guardian, visibility: visibility),
            childAssentDisplay: consentDisplay(childAssent, kind: .child, visibility: visibility),
            decision: decision,
            revocationPlan: revocationPlan,
            audit: audit,
            findings: findings,
            publicSummary: summary
        )

        // 末端泄漏防护：任何展示字段命中不安全标记则降级为阻断快照。
        return redacts(snapshot)
            ? snapshot
            : blockedSnapshot(
                viewerRole: viewerRole,
                visibility: visibility,
                purpose: purpose,
                ageBand: ageBand,
                code: .publicSummaryLeak,
                message: "公开摘要命中敏感标记，已降级为阻断。"
            )
    }

    /// 快照展示字段是否全部安全（不泄漏内部引用）。
    func redacts(_ snapshot: GuardianChildConsentPolicySnapshot) -> Bool {
        !hasUnsafeDisplayValues(displayValues(snapshot))
    }

    // MARK: - 角色可见性

    private func visibility(for role: GuardianChildConsentPolicyViewerRole) -> GuardianChildConsentPolicyVisibility {
        switch role {
        case .guardian:
            return GuardianChildConsentPolicyVisibility(
                viewerRole: role,
                canSeeInternalConsentState: true,
                canSeeGuardianReason: true,
                canSeeRelativePermissionDetail: true,
                canSeeTeacherInternalNote: true,
                canSeeAuditDetail: true
            )
        case .child:
            return GuardianChildConsentPolicyVisibility(
                viewerRole: role,
                canSeeInternalConsentState: true,
                canSeeGuardianReason: false,
                canSeeRelativePermissionDetail: false,
                canSeeTeacherInternalNote: false,
                canSeeAuditDetail: false
            )
        case .relative:
            return GuardianChildConsentPolicyVisibility(
                viewerRole: role,
                canSeeInternalConsentState: false,
                canSeeGuardianReason: false,
                canSeeRelativePermissionDetail: false,
                canSeeTeacherInternalNote: false,
                canSeeAuditDetail: false
            )
        case .teacher:
            return GuardianChildConsentPolicyVisibility(
                viewerRole: role,
                canSeeInternalConsentState: false,
                canSeeGuardianReason: false,
                canSeeRelativePermissionDetail: false,
                canSeeTeacherInternalNote: true,
                canSeeAuditDetail: false
            )
        case .publicViewer:
            return GuardianChildConsentPolicyVisibility(
                viewerRole: role,
                canSeeInternalConsentState: false,
                canSeeGuardianReason: false,
                canSeeRelativePermissionDetail: false,
                canSeeTeacherInternalNote: false,
                canSeeAuditDetail: false
            )
        }
    }

    private enum ConsentDisplayKind { case guardian, child }

    private func consentDisplay(
        _ state: GuardianChildConsentState,
        kind: ConsentDisplayKind,
        visibility: GuardianChildConsentPolicyVisibility
    ) -> String {
        // 公开访客不得看到任何内部同意状态。
        guard visibility.canSeeInternalConsentState else { return "不可见" }
        return state.label
    }

    // MARK: - 决策投影

    // swiftlint:disable:next function_parameter_count
    private func decision(
        state: GuardianChildConsentPolicyState,
        purpose: GuardianChildConsentPolicyPurpose,
        viewerRole: GuardianChildConsentPolicyViewerRole,
        guardianUsable: Bool,
        childAssent: GuardianChildConsentState,
        assentRequired: Bool,
        relativeAuthorized: Bool,
        teacherAuthorized: Bool,
        verifiedSchoolRoster: Bool,
        exportRequested: Bool,
        deleteRequested: Bool,
        requiresManualReview: Bool
    ) -> GuardianChildConsentVisibilityDecision {
        let allowed = state == .allowed
        let assentOK = !assentRequired || childAssent == .granted
        let baseUsable = allowed && guardianUsable && assentOK

        let relativeVisible = baseUsable && purpose.isRelativeFacing && relativeAuthorized
        let schoolVisible = baseUsable && purpose.isSchoolFacing && teacherAuthorized && verifiedSchoolRoster
        let publicVisible = baseUsable && purpose.isPublicFacing
        return GuardianChildConsentVisibilityDecision(
            familyVisible: baseUsable,
            relativeVisible: relativeVisible,
            schoolVisible: schoolVisible,
            publicVisible: publicVisible,
            exportAllowed: baseUsable && purpose == .dataExportDelete && exportRequested,
            deleteAllowed: baseUsable && purpose == .dataExportDelete && deleteRequested,
            childCanWithdraw: true,
            requiresManualReview: requiresManualReview || state == .gated
        )
    }

    // MARK: - 阻断快照

    private func blockedSnapshot(
        viewerRole: GuardianChildConsentPolicyViewerRole,
        visibility: GuardianChildConsentPolicyVisibility,
        purpose: GuardianChildConsentPolicyPurpose,
        ageBand: GuardianChildConsentAgeBand,
        code: GuardianChildConsentPolicyFindingCode,
        message: String
    ) -> GuardianChildConsentPolicySnapshot {
        let findings = [
            finding(code, .blocker, message, "blocked"),
            finding(.sideEffectFree, .ok, "本地只读投影：不写库、不发成长积分、不通知、不接 AI / 学校 / 设备。", "side-effect")
        ]
        let decision = GuardianChildConsentVisibilityDecision(
            familyVisible: false,
            relativeVisible: false,
            schoolVisible: false,
            publicVisible: false,
            exportAllowed: false,
            deleteAllowed: false,
            childCanWithdraw: true,
            requiresManualReview: true
        )
        let summary = GuardianChildConsentPolicyPublicSummary(
            generatedAt: generatedAt,
            viewerRole: viewerRole,
            state: .blocked,
            purpose: purpose,
            policyPublicRef: stableRef("pol", "\(purpose.rawValue):blocked"),
            requestPublicRef: stableRef("req", "\(purpose.rawValue):blocked"),
            familyPublicRef: stableRef("fam", "family-self"),
            childPublicRef: stableRef("kid", "child-self"),
            guardianPublicRef: stableRef("grd", "guardian-self"),
            findingCodes: findings.map(\.code),
            guardianConsentGranted: false,
            childAssentGranted: false,
            relativeVisible: false,
            schoolVisible: false,
            publicVisible: false,
            exportAllowed: false,
            deleteAllowed: false,
            revocationApplied: false
        )
        return GuardianChildConsentPolicySnapshot(
            generatedAt: generatedAt,
            state: .blocked,
            purpose: purpose,
            ageBand: ageBand,
            headline: "同意策略已阻断 · \(purpose.label)",
            childSafeCopy: childCopy(state: .blocked),
            audienceNote: viewerRole.audienceNote,
            visibility: visibility,
            guardianConsentDisplay: consentDisplay(.pending, kind: .guardian, visibility: visibility),
            childAssentDisplay: consentDisplay(.pending, kind: .child, visibility: visibility),
            decision: decision,
            revocationPlan: GuardianChildConsentRevocationPlan(
                revocationRequired: false,
                revocationApplied: false,
                deletionSuppressedVisibility: true,
                pendingTargetCount: 0
            ),
            audit: GuardianChildConsentAuditSummary(linkedEventCount: 3, missingEventCount: 1),
            findings: findings,
            publicSummary: summary
        )
    }

    // MARK: - 文案

    private func headline(
        state: GuardianChildConsentPolicyState,
        purpose: GuardianChildConsentPolicyPurpose,
        viewerRole: GuardianChildConsentPolicyViewerRole
    ) -> String {
        if viewerRole == .child { return childCopy(state: state) }
        return "\(purpose.label) · \(state.label)"
    }

    private func childCopy(state: GuardianChildConsentPolicyState) -> String {
        switch state {
        case .allowed: return "这条分享已经过家长同意，可以放心查看。"
        case .gated: return "这一步要等家长再确认一下。"
        case .blocked: return "这条内容暂时被保护起来，可以和家长一起看。"
        }
    }

    private func finding(
        _ code: GuardianChildConsentPolicyFindingCode,
        _ severity: GuardianChildConsentPolicySeverity,
        _ message: String,
        _ seed: String
    ) -> GuardianChildConsentPolicyFinding {
        GuardianChildConsentPolicyFinding(
            code: code,
            severity: severity,
            message: message,
            publicRef: stableRef("find", "\(code.rawValue):\(seed)")
        )
    }

    // MARK: - 稳定脱敏引用

    /// 与 salt + prefix + source 绑定的确定性脱敏引用，不含任何原始标识。
    func stableRef(_ prefix: String, _ source: String) -> String {
        let input = "\(redactionSalt):\(prefix):\(source)"
        let seeds: [UInt64] = [0xcbf29ce484222325, 0x84222325cbf29ce4]
        let parts = seeds.map { seed -> String in
            var hash = seed
            for scalar in input.unicodeScalars {
                hash ^= UInt64(scalar.value)
                hash = hash &* 0x100000001b3
            }
            return String(String(hash, radix: 36).suffixPadded(to: 13))
        }
        return "\(prefix):\(parts.joined())"
    }

    private func hasUnsafeDisplayValues(_ values: [String]) -> Bool {
        let text = values.joined(separator: " ")
        let unsafeRegex = [
            "(?i)\\bBearer\\s+",
            "(?i)\\bapi[_-]?key\\b",
            "(?i)\\bdevice-token\\b",
            "(?i)\\bserver-secret\\b",
            "(?i)\\bsk-[a-z0-9_-]{8,}\\b",
            "(?i)data:image/",
            "[A-Z]:\\\\",
            "(?i)file://",
            "\\b(?:192\\.168|10\\.[0-9]{1,3}|172\\.(?:1[6-9]|2[0-9]|3[01]))\\.[0-9]{1,3}\\.[0-9]{1,3}\\b",
            "(?i)\\b[a-z0-9-]+\\.local(?::|/|\\b)"
        ]
        if unsafeRegex.contains(where: { text.range(of: $0, options: .regularExpression) != nil }) {
            return true
        }
        let markers = [
            "child:", "family:", "guardian:", "relative:", "teacher:", "school:", "consent:",
            "policy:", "session:", "transcript:", "provider:", "model:", "source:", "taskId",
            "claimId", "baseUrl", "endpoint=", "Bearer ", "api_key", "sk-", "192.168.",
            ".local", "file://", "/Users/", "/Volumes/"
        ]
        return markers.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private func displayValues(_ snapshot: GuardianChildConsentPolicySnapshot) -> [String] {
        var values = [
            snapshot.headline,
            snapshot.childSafeCopy,
            snapshot.audienceNote,
            snapshot.guardianConsentDisplay,
            snapshot.childAssentDisplay,
            snapshot.publicSummary.policyPublicRef,
            snapshot.publicSummary.requestPublicRef,
            snapshot.publicSummary.familyPublicRef,
            snapshot.publicSummary.childPublicRef,
            snapshot.publicSummary.guardianPublicRef
        ]
        values.append(contentsOf: snapshot.findings.flatMap { [$0.publicRef, $0.message] })
        return values
    }
}

private extension String {
    func suffixPadded(to length: Int) -> String {
        if count >= length { return String(suffix(length)) }
        return String(repeating: "0", count: length - count) + self
    }
}
