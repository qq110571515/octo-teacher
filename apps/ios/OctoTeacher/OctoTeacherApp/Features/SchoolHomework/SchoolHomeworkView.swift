import PhotosUI
import SwiftUI

/// 孩子端学校作业视图。
///
/// 展示学校作业、AI 引导式提示、证明提交入口和完成状态。
/// AI 引导只给提示/清单/下一步，绝不给答案；照片证明仅保存在本机，提交后等待老师或家长验证。
struct SchoolHomeworkView: View {
    @Environment(SchoolFamilyStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                Section("成长记录") {
                    NavigationLink {
                        MobileSchoolHomeworkGrowthPackLinkageWorkbenchView(
                            initialRole: .child,
                            allowedRoles: [.child]
                        )
                    } label: {
                        Label("作业成长包联动", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .accessibilityIdentifier("school-homework-link-growth-pack-linkage")
                    NavigationLink {
                        SchoolGrowthCreditSnapshotView()
                    } label: {
                        Label("学校成长快照", systemImage: "creditcard.and.123")
                    }
                    .accessibilityIdentifier("school-homework-link-credit-snapshot")
                }

                Section("待完成作业") {
                    if store.openHomeworks.isEmpty {
                        Text("今天的作业都完成啦 🎉")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(store.openHomeworks.enumerated()), id: \.element.id) { index, homework in
                            NavigationLink {
                                SchoolHomeworkDetailView(homeworkId: homework.id)
                            } label: {
                                HomeworkRow(homework: homework)
                            }
                            .accessibilityIdentifier("school-homework-open-row-\(index)")
                        }
                    }
                }

                Section("已提交 / 已完成") {
                    if store.settledHomeworks.isEmpty {
                        Text("还没有已提交的作业")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.settledHomeworks) { homework in
                            NavigationLink {
                                SchoolHomeworkDetailView(homeworkId: homework.id)
                            } label: {
                                HomeworkRow(homework: homework)
                            }
                            .accessibilityIdentifier("school-homework-settled-row-\(homework.id.uuidString)")
                        }
                    }
                }
            }
            .navigationTitle("学校作业")
        }
    }
}

private struct HomeworkRow: View {
    let homework: SchoolHomework

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Label(homework.subject.label, systemImage: homework.subject.systemImage)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                HomeworkStatusBadge(status: homework.status)
            }
            Text(homework.title)
                .font(.headline)
            Text("截止：\(homework.dueLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct HomeworkStatusBadge: View {
    let status: HomeworkStatus

    var body: some View {
        Text(status.label)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }

    private var tint: Color {
        switch status {
        case .assigned: return .blue
        case .inProgress: return .orange
        case .submitted: return .purple
        case .verified: return .green
        case .returned: return .red
        }
    }
}

/// 学校作业详情：说明、AI 引导式提示、证明提交入口、完成状态。
struct SchoolHomeworkDetailView: View {
    @Environment(SchoolFamilyStore.self) private var store
    @Environment(MobileOfflineOutboxStore.self) private var offlineOutbox
    @Environment(MobileOfflineReplayStore.self) private var offlineReplay
    let homeworkId: UUID

    @State private var proofText: String = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var photoFileName: String?
    @State private var photoLoadFailed = false
    @State private var showCamera = false
    @State private var offlineHint: String?

    private let composer = MobileOfflineActionComposer()

    private var homework: SchoolHomework? {
        store.homeworks.first(where: { $0.id == homeworkId })
    }

    var body: some View {
        Group {
            if let homework {
                content(for: homework)
            } else {
                ContentUnavailableView("作业不存在", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle("作业详情")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let homework {
                proofText = homework.proof.text
                photoFileName = homework.proof.photoFileName
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await loadPhoto(from: newItem)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView { image in
                savePhoto(image)
            }
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func content(for homework: SchoolHomework) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(homework.subject.label, systemImage: homework.subject.systemImage)
                            .font(.subheadline.bold())
                        Spacer()
                        HomeworkStatusBadge(status: homework.status)
                    }
                    Text(homework.title)
                        .font(.title3.bold())
                    Text(homework.instructions)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("截止：\(homework.dueLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            aiGuidanceSection(homework.guidance)

            Section {
                NavigationLink {
                    AIHomeworkGuidanceSessionView(homeworkId: homework.id)
                } label: {
                    Label("打开 AI 作业引导会话", systemImage: "bubble.left.and.text.bubble.right")
                }
                .accessibilityIdentifier("school-homework-detail-ai-guidance")
                NavigationLink {
                    AIHomeworkSchoolCreditHandoffView(homeworkId: homework.id, initialRole: .child)
                } label: {
                    Label("查看作业交接复核", systemImage: "arrow.triangle.branch")
                }
                .accessibilityIdentifier("school-homework-detail-credit-handoff")
                NavigationLink {
                    AIHomeworkFamilySchoolInboxView(initialRole: .child)
                } label: {
                    Label("查看家校作业收件箱", systemImage: "tray.full")
                }
                .accessibilityIdentifier("school-homework-detail-family-school-inbox")
                NavigationLink {
                    AIHomeworkSchoolLmsBoundaryView(homeworkId: homework.id, initialRole: .child, allowsRoleSwitching: false)
                } label: {
                    Label("查看 AI/LMS 边界", systemImage: "shield")
                }
                .accessibilityIdentifier("school-homework-detail-lms-boundary")
            } footer: {
                Text("和 AI 一步步把题目想明白，AI 只给提示，不给答案。")
            }

            if homework.status.acceptsSubmission {
                submissionSection(for: homework)
            } else {
                Section("完成状态") {
                    Label(homework.status.label, systemImage: completionIcon(homework.status))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("school-homework-detail-status-\(homework.status.rawValue)")
                    if homework.proof.hasContent, homework.proof.kind == .text, !homework.proof.text.isEmpty {
                        Text("已提交：\(homework.proof.text)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("school-homework-detail-submitted-proof")
                    }
                    if let fileName = homework.proof.photoFileName,
                       let image = ProofPhotoStore.shared.loadImage(fileName: fileName) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .accessibilityLabel("已提交的作业证明照片")
                    } else if homework.proof.photoPlaceholderName != nil {
                        // 旧数据兼容：早期占位证明用中性文案展示。
                        Label("已提交照片证明记录", systemImage: "photo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let offlineHint {
                Section("离线提交状态") {
                    Label(offlineHint, systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("school-homework-detail-offline-hint")
                }
            }

            MobileOfflineReplaySummarySection(
                report: offlineReplay.report,
                focus: [.schoolHomeworkSubmission]
            ) {
                offlineReplay.replay(outbox: offlineOutbox)
            }

            // 孩子视角：只导航到复核台看安全同步状态，不暴露冲突/回滚。
            MobileOfflineSyncReviewNavigationLink(perspective: .child)
                .accessibilityIdentifier("mobile-offline-sync-review-link-child")
        }
    }

    @ViewBuilder
    private func aiGuidanceSection(_ guidance: AIHomeworkGuidance) -> some View {
        if guidance.hasContent {
            Section {
                if !guidance.hints.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(guidance.hints.enumerated()), id: \.offset) { _, hint in
                            Label {
                                Text(hint).font(.subheadline)
                            } icon: {
                                Image(systemName: "lightbulb")
                                    .foregroundStyle(.yellow)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                if !guidance.checklist.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("提交前自检")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        ForEach(Array(guidance.checklist.enumerated()), id: \.offset) { _, item in
                            Label {
                                Text(item).font(.subheadline)
                            } icon: {
                                Image(systemName: "checklist")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                if !guidance.nextStep.isEmpty {
                    Label {
                        Text(guidance.nextStep).font(.subheadline)
                    } icon: {
                        Image(systemName: "arrow.forward.circle")
                            .foregroundStyle(.green)
                    }
                }
            } header: {
                Text("AI 引导提示")
            } footer: {
                Text("AI 只会给思路和提示，帮你自己想出答案，不会直接告诉你答案。")
            }
        }
    }

    @ViewBuilder
    private func submissionSection(for homework: SchoolHomework) -> some View {
        Section {
            if homework.requiredProof == .text {
                TextField("用一句话说说你完成的情况", text: $proofText, axis: .vertical)
                    .lineLimit(2...4)
                    .accessibilityIdentifier("school-homework-detail-proof-text")
            } else {
                homeworkPhotoInput
            }

            Button {
                submit(homework)
            } label: {
                Label("提交作业证明", systemImage: "paperplane")
            }
            .disabled(!canSubmit(homework))
            .accessibilityIdentifier("school-homework-detail-submit-proof")
        } header: {
            Text("提交证明")
        } footer: {
            Text("提交后会进入「待验证」，由老师或家长确认完成，不会自动发放奖励。")
        }
    }

    private func canSubmit(_ homework: SchoolHomework) -> Bool {
        switch homework.requiredProof {
        case .text:
            return !proofText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .photoPlaceholder, .photo:
            // 旧的 photoPlaceholder 作业对孩子来说就是照片证明：必须拍照或选图。
            return photoFileName != nil
        }
    }

    private func submit(_ homework: SchoolHomework) {
        let proof: ProofDraft
        switch homework.requiredProof {
        case .text:
            proof = ProofDraft(kind: .text, text: proofText, photoPlaceholderName: nil, status: .drafting)
        case .photoPlaceholder:
            // 新提交必须带真实照片；photoPlaceholderName 仅存在于旧数据，不再生成。
            proof = ProofDraft(
                kind: .photoPlaceholder,
                text: proofText,
                photoPlaceholderName: nil,
                photoFileName: photoFileName,
                status: .drafting
            )
        case .photo:
            proof = ProofDraft(
                kind: .photo,
                text: proofText,
                photoPlaceholderName: nil,
                photoFileName: photoFileName,
                status: .drafting
            )
        }
        _ = store.submitHomework(homework, proof: proof)
        let request = composer.schoolHomeworkSubmission(
            homeworkSeed: homework.id.uuidString,
            subjectLabel: homework.subject.label
        )
        offlineHint = MobileOfflineEnqueueFeedback.message(
            for: offlineOutbox.enqueue(request),
            successText: "已加入离线队列，等老师/家长验证"
        )
        proofText = ""
        photoFileName = nil
        selectedPhotoItem = nil
        photoLoadFailed = false
    }

    @ViewBuilder
    private var homeworkPhotoInput: some View {
        if let photoFileName,
           let image = ProofPhotoStore.shared.loadImage(fileName: photoFileName) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel("已选择的作业证明照片")
        }

        if CameraCaptureView.isCameraAvailable {
            Button {
                showCamera = true
            } label: {
                Label(photoFileName == nil ? "直接拍作业证明" : "重新拍作业证明", systemImage: "camera")
            }
            .accessibilityIdentifier("school-homework-detail-camera")
        }

        let photoPickerLabel = photoFileName == nil ? "从相册选择照片" : "从相册换一张"
        HStack {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Label(photoPickerLabel, systemImage: "photo.on.rectangle")
            }
            .accessibilityIdentifier("school-homework-detail-photo-picker")
            Spacer()
        }

        if photoLoadFailed {
            Text("照片没有读出来，再选一次试试。")
                .font(.caption)
                .foregroundStyle(.red)
        }

        Text("照片只保存在本机，提交后等待老师或家长验证。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func savePhoto(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.9),
              let fileName = ProofPhotoStore.shared.save(imageData: data) else {
            photoLoadFailed = true
            return
        }
        if let previous = photoFileName, previous != fileName {
            ProofPhotoStore.shared.delete(fileName: previous)
        }
        photoFileName = fileName
        photoLoadFailed = false
    }

    private func loadPhoto(from item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let fileName = ProofPhotoStore.shared.save(imageData: data) else {
            photoLoadFailed = true
            return
        }
        if let previous = photoFileName, previous != fileName {
            ProofPhotoStore.shared.delete(fileName: previous)
        }
        photoFileName = fileName
        photoLoadFailed = false
    }

    private func completionIcon(_ status: HomeworkStatus) -> String {
        switch status {
        case .verified: return "checkmark.seal.fill"
        case .submitted: return "hourglass"
        default: return "circle"
        }
    }
}
