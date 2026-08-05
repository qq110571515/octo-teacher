import SwiftUI

/// 离线同步复核台的可复用入口（多页签统一桥接）。
///
/// 放在各页面既有离线重放摘要旁边，导航到现有 `MobileOfflineSyncReviewView`。
/// 入口只做导航，**不触发 replay、不落定业务、不写账本、不发成长积分、不扣成长积分、不解锁设备**，
/// 也不接真实网络、云端、AI、LMS、学校系统、FamilyControls、HealthKit 或通知。
///
/// 文案来自纯配置 `MobileOfflineSyncReviewEntryCopy`：孩子页面传 `.child` 只显示安全同步状态；
/// 家长审批页传 `.parent`，进入后可看冲突 / 回滚摘要（裁剪仍由复核台 presenter 裁决）。
struct MobileOfflineSyncReviewNavigationLink: View {
    let perspective: MobileHomePerspective

    private var copy: MobileOfflineSyncReviewEntryCopy {
        MobileOfflineSyncReviewEntryCopy(perspective: perspective)
    }

    var body: some View {
        Section {
            NavigationLink {
                MobileOfflineSyncReviewView(perspective: perspective)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(copy.title)
                            .font(.subheadline.weight(.semibold))
                        Text(copy.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: copy.systemImage)
                }
            }
            .accessibilityIdentifier("mobile-offline-sync-review-link-\(perspective.rawValue)")
        } footer: {
            Text("进入本地只读复核台查看完整同步状态，不会自动同步，也不发积分、不解锁设备。")
        }
    }
}
