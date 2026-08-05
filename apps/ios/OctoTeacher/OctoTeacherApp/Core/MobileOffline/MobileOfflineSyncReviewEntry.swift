import Foundation

/// 离线同步复核台「多页签统一入口」的**纯文案配置**。
///
/// 任务详情、学校作业、奖励兑换、家长审批等页面各自挨着既有离线重放摘要放一个
/// 进入 `MobileOfflineSyncReviewView` 的统一入口。入口本身只是**导航文案**，
/// 不触发任何 replay、不落定任何业务。设计约束（与 CLAUDE.md 一致）：
///
/// - **纯文案**：只产出标题、副标题、图标名，不读写任何 store、不接网络/云/AI/账本/设备。
/// - **角色裁剪**：孩子入口只描述「看安全同步状态和下一步」，绝不出现冲突、回滚、
///   写账本、ledger、成人复核内部原因或设备控制承诺等字样；家长入口才说明
///   待同步 / 冲突 / 回滚摘要，并明确本地只读、不写账本、不发成长积分、不解锁设备。
/// - **脱敏**：文案为固定常量，绝不拼接真实 child/family/school/pack/order/entitlement/
///   homework/session/device/ledger/ref、token、路径、局域网地址、taskId 或 claimId。
struct MobileOfflineSyncReviewEntryCopy: Equatable {
    /// 入口进入复核台时使用的视角。
    let perspective: MobileHomePerspective
    /// 入口标题。
    let title: String
    /// 入口副标题（按视角裁剪）。
    let subtitle: String
    /// 入口图标（SF Symbol 名）。
    let systemImage: String

    init(perspective: MobileHomePerspective) {
        self.perspective = perspective
        switch perspective {
        case .child:
            // 孩子入口只描述安全的同步进度与下一步，不暴露任何成人复核语义。
            title = "同步复核台"
            subtitle = "看看哪些动作已经同步、哪些还在等家长或老师处理。"
            systemImage = "checklist"
        case .parent:
            // 家长入口才提到待同步 / 冲突 / 回滚摘要，并明确本地只读、不落定。
            title = "离线同步复核台"
            subtitle = "查看待同步、冲突与回滚摘要；本地只读，不写账本、不发成长积分、不解锁设备。"
            systemImage = "arrow.triangle.2.circlepath"
        }
    }
}
