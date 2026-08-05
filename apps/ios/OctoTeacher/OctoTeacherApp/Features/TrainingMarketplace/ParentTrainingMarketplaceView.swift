import SwiftUI

/// 家长端培训市场本地第一版。
///
/// 浏览与安装已经走真实家庭任务数据；目录当前来自本地适配器，明确不联网、不支付。
struct ParentTrainingMarketplaceView: View {
    @Environment(LocalFamilyStore.self) private var store

    private let provider: any TrainingMarketplaceCatalogProviding
    private let cloudProvider: any TrainingMarketplaceCloudCatalogLoading
    @State private var searchText = ""
    @State private var selectedCategory: TrainingMarketplaceCategory = .all
    @State private var listings: [TrainingMarketplaceListing]
    @State private var catalogStatus: TrainingMarketplaceCatalogStatus = .loading

    init(
        provider: any TrainingMarketplaceCatalogProviding = LocalTrainingMarketplaceCatalogProvider(),
        cloudProvider: any TrainingMarketplaceCloudCatalogLoading = CloudTrainingMarketplaceCatalogProvider()
    ) {
        self.provider = provider
        self.cloudProvider = cloudProvider
        _listings = State(initialValue: provider.listings())
    }

    private var language: AppInterfaceLanguage {
        store.settings.resolvedParentInterfaceLanguage
    }

    private var visibleListings: [TrainingMarketplaceListing] {
        listings.filter { listing in
            let matchesCategory = selectedCategory == .all || listing.category == selectedCategory
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return matchesCategory }
            let searchable = [
                listing.title,
                listing.titleEnglish,
                listing.summary,
                listing.summaryEnglish,
                listing.creator.displayName,
                listing.creator.displayNameEnglish
            ] + listing.tags + listing.tagsEnglish
            return matchesCategory && searchable.contains {
                $0.localizedCaseInsensitiveContains(query)
            }
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        language.pick("先预览，再安装", "Preview before installing"),
                        systemImage: "checkmark.shield.fill"
                    )
                    .font(.headline)
                    Text(language.pick(
                        "选择孩子、查看每天安排并调整积分与证明方式；确认后任务才会进入现有任务中心。",
                        "Choose a child, review the daily plan, and adjust points and proof. Tasks enter the existing Task Center only after confirmation."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                Picker(language.pick("分类", "Category"), selection: $selectedCategory) {
                    ForEach(TrainingMarketplaceCategory.allCases) { category in
                        Label(category.label(for: language), systemImage: category.systemImage)
                            .tag(category)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("training-marketplace-category")

                catalogStatusRow
            } footer: {
                Text(language.pick(
                    "培训市场只同步公开目录。孩子资料、设备信息和安装记录留在本机；价格只做预览，不会创建订单或扣款。",
                    "The marketplace syncs only the public catalog. Child, device, and installation data stay on this device; prices are previews and never create an order or charge."
                ))
            }

            Section {
                if visibleListings.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ForEach(visibleListings) { listing in
                        NavigationLink {
                            ParentTrainingMarketplaceDetailView(listing: listing)
                        } label: {
                            TrainingMarketplaceListingRow(
                                listing: listing,
                                language: language,
                                installedChildCount: installedChildCount(for: listing)
                            )
                        }
                        .accessibilityIdentifier("training-marketplace-listing-\(listing.id)")
                    }
                }
            } header: {
                Text(language.pick("培训内容", "Programs"))
            }
        }
        .navigationTitle(language.pick("培训市场", "Learning Marketplace"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            prompt: language.pick("搜索任务包、图书或创作者", "Search packs, books, or creators")
        )
        .task { await reloadCatalog() }
        .refreshable { await reloadCatalog() }
    }

    @ViewBuilder
    private var catalogStatusRow: some View {
        switch catalogStatus {
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text(language.pick("正在同步云端目录", "Syncing cloud catalog"))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("training-marketplace-cloud-loading")
        case .cloud:
            Label(
                language.pick("章鱼老师 云端目录已同步", "章鱼老师 cloud catalog synced"),
                systemImage: "checkmark.icloud.fill"
            )
            .font(.subheadline)
            .foregroundStyle(.green)
            .accessibilityIdentifier("training-marketplace-cloud-synced")
        case .localFallback:
            HStack {
                Label(
                    language.pick("网络不可用，正在显示本地官方目录", "Offline: showing the local official catalog"),
                    systemImage: "icloud.slash"
                )
                Spacer()
                Button(language.pick("重试", "Retry")) {
                    Task { await reloadCatalog() }
                }
                .buttonStyle(.borderless)
            }
            .font(.subheadline)
            .foregroundStyle(.orange)
            .accessibilityIdentifier("training-marketplace-local-fallback")
        }
    }

    @MainActor
    private func reloadCatalog() async {
        catalogStatus = .loading
        do {
            let cloudListings = try await cloudProvider.loadListings()
            guard !cloudListings.isEmpty else {
                catalogStatus = .localFallback
                return
            }
            listings = cloudListings
            catalogStatus = .cloud
        } catch {
            listings = provider.listings()
            catalogStatus = .localFallback
        }
    }

    private func installedChildCount(for listing: TrainingMarketplaceListing) -> Int {
        Set(
            store.trainingMarketplaceInstallations
                .filter { $0.listingID == listing.id }
                .map(\.childID)
        ).count
    }
}

private enum TrainingMarketplaceCatalogStatus {
    case loading
    case cloud
    case localFallback
}

private struct TrainingMarketplaceListingRow: View {
    let listing: TrainingMarketplaceListing
    let language: AppInterfaceLanguage
    let installedChildCount: Int

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: listing.category.systemImage)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(listing.localizedTitle(language))
                        .font(.headline)
                    if listing.creator.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .accessibilityLabel(language.pick("已验证创作者", "Verified creator"))
                    }
                }
                Text(listing.localizedSummary(language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                HStack(spacing: 10) {
                    Label(String(format: "%.1f", listing.rating), systemImage: "star.fill")
                    Text(listing.availability.label(for: language))
                    if installedChildCount > 0 {
                        Text(language.pick("已装给 \(installedChildCount) 个孩子", "Installed for \(installedChildCount)"))
                            .foregroundStyle(.green)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private var tint: Color {
        switch listing.category {
        case .all: return .blue
        case .routines: return .orange
        case .family: return .indigo
        case .learning: return .blue
        case .outdoor: return .green
        case .creativity: return .purple
        case .library: return .teal
        }
    }
}

struct ParentTrainingMarketplaceDetailView: View {
    @Environment(LocalFamilyStore.self) private var store

    let listing: TrainingMarketplaceListing

    @State private var selectedChildID: UUID?
    @State private var startDate = Date()
    @State private var pace: TrainingMarketplaceInstallPace = .balanced
    @State private var usesCustomPoints = false
    @State private var customPoints = 15
    @State private var proofPreference: TrainingMarketplaceProofPreference = .followPlan
    @State private var showsInstallConfirmation = false
    @State private var resultMessage: String?
    @State private var showsResult = false

    init(listing: TrainingMarketplaceListing) {
        self.listing = listing
    }

    private var language: AppInterfaceLanguage {
        store.settings.resolvedParentInterfaceLanguage
    }

    private var selectedChild: ChildProfile? {
        guard let selectedChildID else { return nil }
        return store.children.first { $0.id == selectedChildID }
    }

    private var installation: TrainingMarketplaceInstallationRecord? {
        guard let selectedChildID else { return nil }
        return store.marketplaceInstallation(
            listingID: listing.id,
            childID: selectedChildID
        )
    }

    private var isAgeAppropriate: Bool {
        guard let selectedChild else { return false }
        return (listing.minAge...listing.maxAge).contains(selectedChild.age)
    }

    var body: some View {
        List {
            overviewSection
            creatorSection
            planSection
            reviewSection
            actionSection
        }
        .navigationTitle(listing.localizedTitle(language))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedChildID == nil {
                selectedChildID = store.activeChildId
            }
        }
        .confirmationDialog(
            language.pick("确认安装这个任务包？", "Install this pack?"),
            isPresented: $showsInstallConfirmation,
            titleVisibility: .visible
        ) {
            Button(language.pick("确认安装", "Install")) {
                install()
            }
            Button(language.pick("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
        .alert(
            language.pick("培训市场", "Learning Marketplace"),
            isPresented: $showsResult
        ) {
            Button(language.pick("知道了", "OK"), role: .cancel) {}
        } message: {
            Text(resultMessage ?? "")
        }
    }

    private var overviewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(listing.localizedSummary(language))
                    .font(.headline)
                Text(listing.localizedDetail(language))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    Label("\(listing.minAge)-\(listing.maxAge)", systemImage: "person.2")
                    if listing.durationDays > 0 {
                        Label(
                            language.pick("\(listing.durationDays) 天", "\(listing.durationDays) days"),
                            systemImage: "calendar"
                        )
                    }
                    Label("v\(listing.version)", systemImage: "number")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(listing.localizedTags(language), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.secondary.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        } footer: {
            if case .pricePreview = listing.availability {
                Text(language.pick(
                    "价格仅用于产品预览；当前没有购买、订单、退款或付款功能。",
                    "Price is for product preview only. Purchasing, orders, refunds, and payments are not available."
                ))
            }
        }
    }

    private var creatorSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.title2)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(listing.creator.localizedName(language))
                        .font(.headline)
                    Text(listing.creator.localizedBio(language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(language.pick(
                        "评分 \(String(format: "%.1f", listing.creator.rating)) · \(listing.creator.verifiedFamilyCount) 个验证家庭",
                        "Rating \(String(format: "%.1f", listing.creator.rating)) · \(listing.creator.verifiedFamilyCount) verified families"
                    ))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(language.pick("创作者", "Creator"))
        }
    }

    @ViewBuilder
    private var planSection: some View {
        if listing.isLibraryEntry {
            Section {
                NavigationLink {
                    ParentBookCenterView()
                } label: {
                    Label(language.pick("打开家庭图书馆", "Open Family Library"), systemImage: "books.vertical")
                }
                .accessibilityIdentifier("training-marketplace-open-book-center")

                NavigationLink {
                    ParentAIReadingComposerView()
                } label: {
                    Label(language.pick("挑选并布置阅读", "Choose and assign reading"), systemImage: "wand.and.stars")
                }
            } header: {
                Text(language.pick("图书入口", "Library"))
            } footer: {
                Text(language.pick(
                    "下载图书不会自动生成任务；家长确认书目和章节后再布置。",
                    "Downloading a book never creates a task automatically. Parents confirm the book and chapters first."
                ))
            }
        } else if listing.isResourceCollection {
            Section {
                let books = listing.resources.filter { $0.kind == .book }.count
                let videos = listing.resources.filter { $0.kind == .video }.count
                if books > 0 {
                    Label(
                        language.pick("安装后加入图书馆：\(books) 本", "Adds \(books) books to Library"),
                        systemImage: "books.vertical.fill"
                    )
                }
                if videos > 0 {
                    Label(
                        language.pick("安装后加入教育视频：\(videos) 条", "Adds \(videos) items to Educational Videos"),
                        systemImage: "play.rectangle.fill"
                    )
                }
                ForEach(listing.resources.prefix(8)) { resource in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(resource.localizedTitle(language))
                            .font(.subheadline.weight(.semibold))
                        Text(resource.localizedSummary(language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                if listing.resources.count > 8 {
                    Text(language.pick(
                        "还有 \(listing.resources.count - 8) 项，安装后可在对应内容中心筛选。",
                        "\(listing.resources.count - 8) more items become searchable after installation."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text(language.pick("内容资源预览", "Content Preview"))
            } footer: {
                Text(language.pick(
                    "安装只加入家庭内容库，不会自动下载文件，也不会自动给孩子布置任务。",
                    "Installation adds references to the family content library. It never downloads files or assigns tasks automatically."
                ))
            }
        } else if listing.planItems.isEmpty {
            Section {
                Label(
                    language.pick("创作者内容尚未开放安装", "Creator content is not yet open for installation"),
                    systemImage: "lock.fill"
                )
                    .foregroundStyle(.secondary)
            } header: {
                Text(language.pick("内容预览", "Content Preview"))
            }
        } else {
            Section {
                ForEach(Array(listing.planItems.enumerated()), id: \.offset) { index, item in
                    if let template = item.resolvedTemplate() {
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(localizedTemplateTitle(template))
                                    .font(.subheadline.weight(.semibold))
                                Text(scheduleLabel(item: item, index: index))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(usesCustomPoints ? customPoints : template.suggestedRewardMinutes)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                    }
                }
            } header: {
                Text(language.pick("任务预览", "Task Preview"))
            } footer: {
                Text(language.pick(
                    "安装后，家务、户外、创作等任务仍回到各自模块；证明提交后仍需家长审核。",
                    "After installation, chores, outdoor, and creative tasks return to their existing modules. Parent approval is still required."
                ))
            }
        }
    }

    private var reviewSection: some View {
        Section {
            ForEach(listing.reviews) { review in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(review.localizedTitle(language))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(String(repeating: "★", count: review.rating))
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                    Text(review.localizedBody(language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if review.verifiedUse {
                        Label(language.pick("已验证使用", "Verified use"), systemImage: "checkmark.seal")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text(language.pick("验证使用评价", "Verified-use Reviews"))
        } footer: {
            Text(language.pick(
                "本地第一版只读展示评价；云端上线后才开放真实家庭评分和评论。",
                "Reviews are read-only in this local build. Real family ratings and comments open only after cloud launch."
            ))
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        if !listing.isLibraryEntry {
            Section {
                Picker(language.pick("安装给", "Install for"), selection: $selectedChildID) {
                    ForEach(store.children) { child in
                        Text("\(child.name) · \(child.age)")
                            .tag(Optional(child.id))
                    }
                }
                .accessibilityIdentifier("training-marketplace-child-picker")

                if let selectedChild, !isAgeAppropriate {
                    Label(
                        language.pick(
                            "该内容建议 \(listing.minAge)-\(listing.maxAge) 岁，\(selectedChild.name)当前 \(selectedChild.age) 岁。",
                            "Recommended for ages \(listing.minAge)-\(listing.maxAge); \(selectedChild.name) is \(selectedChild.age)."
                        ),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                if !listing.planItems.isEmpty {
                    DatePicker(
                        language.pick("开始日期", "Start date"),
                        selection: $startDate,
                        in: Calendar.current.startOfDay(for: Date())...,
                        displayedComponents: .date
                    )

                    Picker(language.pick("安排节奏", "Schedule"), selection: $pace) {
                        ForEach(TrainingMarketplaceInstallPace.allCases) { option in
                            Text(option.label(for: language)).tag(option)
                        }
                    }

                    Toggle(language.pick("统一调整每项积分", "Override points per task"), isOn: $usesCustomPoints)
                    if usesCustomPoints {
                        Stepper(
                            language.pick("每项 \(customPoints) 成长积分", "\(customPoints) Growth Points each"),
                            value: $customPoints,
                            in: 5...60,
                            step: 5
                        )
                    }

                    Picker(language.pick("完成证明", "Proof"), selection: $proofPreference) {
                        ForEach(TrainingMarketplaceProofPreference.allCases) { option in
                            Text(option.label(for: language)).tag(option)
                        }
                    }
                }

                if let installation {
                    Label(
                        language.pick(
                            "已安装 v\(installation.listingVersion) · \(installation.assignmentIDs.count) 个任务 · \(installation.installedResourceIDs?.count ?? 0) 项内容",
                            "Installed v\(installation.listingVersion) · \(installation.assignmentIDs.count) tasks · \(installation.installedResourceIDs?.count ?? 0) resources"
                        ),
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("training-marketplace-installed")
                } else {
                    Button {
                        showsInstallConfirmation = true
                    } label: {
                        Label(
                            listing.availability.canInstallLocally
                                ? language.pick("确认计划并安装", "Confirm plan and install")
                                : listing.availability.label(for: language),
                            systemImage: listing.availability.canInstallLocally ? "square.and.arrow.down.fill" : "lock.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(!listing.availability.canInstallLocally || selectedChildID == nil || !isAgeAppropriate)
                    .accessibilityIdentifier("training-marketplace-install")
                }
            } header: {
                Text(language.pick("安装预览", "Installation Preview"))
            } footer: {
                Text(language.pick(
                    "安装回执写入家庭数据；不会扣款、自动发积分、自动下载文件或解锁设备。",
                    "The receipt is stored with family data. Installation never charges, grants points, downloads files, or unlocks devices automatically."
                ))
            }
        }
    }
}

private extension ParentTrainingMarketplaceDetailView {
    private var confirmationMessage: String {
        let childName = selectedChild?.name ?? language.pick("所选孩子", "the selected child")
        return language.pick(
            "将为\(childName)安装 \(listing.planItems.count) 个任务和 \(listing.resources.count) 项内容资源。",
            "This installs \(listing.planItems.count) tasks and \(listing.resources.count) content resources for \(childName)."
        )
    }

    private func scheduleLabel(item: TrainingMarketplacePlanItem, index: Int) -> String {
        let offset = pace.dayOffset(catalogOffset: item.dayOffset, index: index)
        if offset == 0 {
            return language.pick("开始日", "Start day")
        }
        return language.pick("第 \(offset + 1) 天", "Day \(offset + 1)")
    }

    private func localizedTemplateTitle(_ template: PackTaskTemplate) -> String {
        guard language == .english else { return template.title }
        return BuiltInTaskLocalization.englishTitle(for: template.title) ?? template.title
    }

    private func install() {
        guard let selectedChildID else { return }
        let configuration = TrainingMarketplaceInstallConfiguration(
            childID: selectedChildID,
            startDate: startDate,
            pace: pace,
            pointsOverride: usesCustomPoints ? customPoints : nil,
            proofPreference: proofPreference
        )
        do {
            let receipt = try store.installTrainingMarketplaceListing(listing, configuration: configuration)
            let resourceCount = receipt.installedResourceIDs?.count ?? 0
            resultMessage = language.pick(
                "安装完成：\(receipt.assignmentIDs.count) 个任务进入任务中心，\(resourceCount) 项内容进入对应内容中心。",
                "Installed: \(receipt.assignmentIDs.count) tasks entered Task Center and \(resourceCount) resources entered their content centers."
            )
        } catch let error as TrainingMarketplaceInstallationError {
            resultMessage = error.message(for: language)
        } catch {
            resultMessage = language.pick("安装失败，请稍后再试。", "Installation failed. Please try again.")
        }
        showsResult = true
    }
}
