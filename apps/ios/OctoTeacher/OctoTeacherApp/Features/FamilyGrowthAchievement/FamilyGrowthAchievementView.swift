import SwiftUI

/// 家庭成长动态「荣誉卡片视图」。
///
/// 按查看者角色（孩子 / 家长 / 亲友）展示成长日记、徽章、成长球星卡、荣誉墙、亲友鼓励、
/// VLOG 占位与故事线摘要，权限不同：
/// - 顶部可切换角色，直观验证隐私边界。
/// - 每张卡片显示可见范围（私密/家庭/亲友/公开）与生命周期状态（待审核/已撤回/已阻断）。
/// - 非正式荣誉（待审核/已撤回/已阻断）不会展示给亲友，也不会被当成正式荣誉。
/// - 全程脱敏：仅展示稳定 `publicRef`，绝不暴露真实 ID、路径或 token。
///
/// 纯本地展示：不发布、不通知亲友、不发成长积分、不授徽章、不上传媒体、不接真实社交/学校/云端。
struct FamilyGrowthAchievementView: View {
    @State private var store = FamilyGrowthAchievementStore()
    @State private var role: FamilyGrowthViewerRole = .child

    private var summary: FamilyGrowthViewerSummary {
        store.summary(for: role)
    }

    var body: some View {
        List {
            roleSection
            overviewSection
            ForEach(orderedKinds, id: \.self) { kind in
                kindSection(kind)
            }
            disclaimerSection
        }
        .navigationTitle("荣誉卡片")
        .navigationBarTitleDisplayMode(.inline)
    }

    // 固定来源顺序展示。
    private var orderedKinds: [FamilyGrowthCardKind] {
        [.storyline, .honorWall, .badge, .growthCard, .journal, .relativeComment, .vlogPlaceholder]
    }

    // MARK: - 角色切换

    private var roleSection: some View {
        Section {
            Picker("视角", selection: $role) {
                ForEach(FamilyGrowthViewerRole.allCases, id: \.self) { role in
                    Text(role.label).tag(role)
                }
            }
            .pickerStyle(.segmented)
            Text(role.audienceNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 概览

    private var overviewSection: some View {
        Section("成长概览") {
            LabeledContent("正式荣誉") {
                Text("\(summary.formalHonorCount)").monospacedDigit()
            }
            if role.isHousehold {
                LabeledContent("待处理（含待审核/已撤回/已阻断）") {
                    Text("\(summary.pendingCount)").monospacedDigit()
                }
            }
            LabeledContent("脱敏家庭引用") {
                Text(summary.familyPublicRef)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            LabeledContent("脱敏孩子引用") {
                Text(summary.childPublicRef)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 单个来源种类分区

    @ViewBuilder
    private func kindSection(_ kind: FamilyGrowthCardKind) -> some View {
        let cards = summary.cards.filter { $0.kind == kind }
        Section(kind.label) {
            if cards.isEmpty {
                Text(role == .relative ? "亲友视角暂无可见内容" : "暂无内容")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(cards) { card in
                    FamilyGrowthCardRow(card: card, role: role)
                }
            }
        }
    }

    // MARK: - 安全说明

    private var disclaimerSection: some View {
        Section {
            Text("本视图仅为本地展示：不发布动态、不通知亲友、不发成长积分、不授徽章、不上传媒体，也不接真实社交、学校或云端。私密内容只有孩子和家长可见；待审核、已撤回、已阻断内容不会作为正式荣誉，也不会对亲友展示。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 卡片行

private struct FamilyGrowthCardRow: View {
    let card: FamilyGrowthCard
    let role: FamilyGrowthViewerRole

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: card.kind.systemImage)
                    .foregroundStyle(.orange)
                Text(card.title).font(.subheadline.bold())
                Spacer()
                Text(card.occurredLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                VisibilityBadge(visibility: card.visibility)
                LifecycleBadge(lifecycle: card.lifecycle)
            }

            Text(card.displaySummary(for: role))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let ratings = card.ratings, let overall = card.overallRating {
                StarCardRatings(ratings: ratings, overall: overall)
            }

            // 支持性文案。
            Label(card.supportiveCopy, systemImage: "heart")
                .font(.caption)
                .foregroundStyle(.pink)

            // 下一步。
            Label(card.nextStep, systemImage: "arrow.forward.circle")
                .font(.caption)
                .foregroundStyle(.secondary)

            // 非正式荣誉的状态说明（仅家庭内部角色可见）。
            if let note = card.statusNote(for: role) {
                Label(note, systemImage: card.lifecycle.systemImage)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            if !card.tags.isEmpty {
                Text(card.tags.map { "#\($0)" }.joined(separator: " "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                Label("\(card.reactionCount)", systemImage: "hands.clap")
                Label("\(card.approvedCommentCount)", systemImage: "text.bubble")
                Spacer()
                Text(card.publicRef)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 小组件

private struct VisibilityBadge: View {
    let visibility: FamilyGrowthCardVisibility
    var body: some View {
        Label(visibility.label, systemImage: visibility.systemImage)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.thinMaterial, in: Capsule())
    }
}

private struct LifecycleBadge: View {
    let lifecycle: FamilyGrowthLifecycle

    private var tint: Color {
        switch lifecycle {
        case .published: return .green
        case .pending: return .orange
        case .withdrawn: return .gray
        case .blocked: return .red
        }
    }

    var body: some View {
        Label(lifecycle.label, systemImage: lifecycle.systemImage)
            .font(.caption2.bold())
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(Capsule().stroke(tint.opacity(0.4)))
    }
}

private struct StarCardRatings: View {
    let ratings: [AbilityDimension: Int]
    let overall: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("综合").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(overall)").font(.subheadline.bold()).monospacedDigit()
            }
            ForEach(AbilityDimension.allCases, id: \.self) { dimension in
                let value = ratings[dimension] ?? 0
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(dimension.label).font(.caption2)
                        Spacer()
                        Text("\(value)").font(.caption2.bold()).monospacedDigit()
                    }
                    ProgressView(value: Double(value), total: 99)
                        .tint(.blue)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
