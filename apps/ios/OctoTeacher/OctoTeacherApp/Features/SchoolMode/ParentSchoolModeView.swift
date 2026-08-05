import SwiftUI

#if canImport(FamilyControls) && canImport(ManagedSettings)
import FamilyControls
#endif

struct ParentSchoolModeView: View {
    @Environment(LocalFamilyStore.self) private var store
    #if canImport(FamilyControls) && canImport(ManagedSettings)
    @Environment(ScreenTimePOCManager.self) private var screenTime
    #endif

    @State private var selectedChildID = UUID()
    @State private var profile = ChildSchoolModeProfile.initial(childID: UUID())
    #if canImport(FamilyControls) && canImport(ManagedSettings)
    @State private var showsPicker = false
    #endif

    private var lang: AppInterfaceLanguage {
        store.settings.resolvedParentInterfaceLanguage
    }

    var body: some View {
        Form {
            childSection
            statusSection
            planningModeSection
            defaultTimeSection
            weekdaySection
            exceptionSection
            mailIntelligenceSection
            dynamicsSection
            deviceSection
        }
        .navigationTitle(lang.pick("学校模式与时间表", "School Mode & Schedule"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedChildID = store.activeChildId
            reloadProfile()
            synchronizeDeviceRule()
        }
        .onChange(of: selectedChildID) { _, _ in
            reloadProfile()
        }
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        .familyActivityPicker(isPresented: $showsPicker, selection: Binding(
            get: { screenTime.selection },
            set: { screenTime.selection = $0 }
        ))
        .onChange(of: showsPicker) { _, presented in
            if !presented {
                screenTime.persistSelection()
                synchronizeDeviceRule()
            }
        }
        #endif
    }

    private var mailIntelligenceSection: some View {
        Section {
            NavigationLink {
                SchoolMailboxExplorerView()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Label(lang.pick("AI 探索学校邮件", "AI School Mail Explorer"), systemImage: "envelope.stack.fill")
                        .font(.subheadline.weight(.semibold))
                    Text(lang.pick(
                        "按学校和孩子整理邮件，自动生成家长摘要与本机成长记忆。",
                        "Organize mail by school and child, then create parent summaries and on-device growth memory."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("school-mode-mail-explorer")

            NavigationLink {
                SchoolMailRecognitionView(childID: selectedChildID) {
                    reloadProfile()
                    synchronizeDeviceRule()
                }
            } label: {
                Label(lang.pick("AI 识别单封学校邮件", "Analyze One School Email"), systemImage: "doc.text.magnifyingglass")
            }
            .accessibilityIdentifier("school-mode-single-mail")
        } header: {
            Text(lang.pick("学校邮件", "School Mail"))
        } footer: {
            Text(lang.pick(
                "邮件只读。AI 自动记忆只保存脱敏摘要；任何时间表变化仍需家长确认。",
                "Mail is read-only. Automatic memory stores only redacted summaries; every schedule change still needs parent confirmation."
            ))
        }
    }

    private var childSection: some View {
        Section {
            Picker(lang.pick("孩子", "Child"), selection: $selectedChildID) {
                ForEach(store.children) { child in
                    Text(child.name).tag(child.id)
                }
            }
        } header: {
            Text(lang.pick("生效对象", "Applies To"))
        } footer: {
            Text(lang.pick(
                "每个孩子保存独立规则。共享手机当前只执行正在使用这台设备的孩子规则。",
                "Each child keeps separate rules. A shared phone enforces only the profile currently using this device."
            ))
        }
    }

    private var statusSection: some View {
        Section {
            Toggle(lang.pick("开启学校模式", "Enable School Mode"), isOn: Binding(
                get: { profile.isEnabled },
                set: { value in
                    profile.isEnabled = value
                    saveProfile()
                }
            ))
            .accessibilityIdentifier("school-mode-enabled")
            let evaluation = SchoolModeRuleEngine.evaluate(profile: profile, at: Date())
            LabeledContent(
                lang.pick("当前状态", "Current Status"),
                value: evaluation.isActive
                    ? lang.pick("学校时段生效中", "School hours active")
                    : lang.pick("当前未锁定", "Not restricted now")
            )
            if evaluation.isActive, let end = evaluation.endsAt {
                LabeledContent(lang.pick("预计解除", "Expected Release"), value: end.formatted(date: .omitted, time: .shortened))
            }
        } header: {
            Text(lang.pick("今天", "Today"))
        }
    }

    private var planningModeSection: some View {
        Section {
            Picker(lang.pick("规划方式", "Planning Method"), selection: Binding(
                get: { profile.source },
                set: { value in
                    profile.source = value
                    saveProfile()
                }
            )) {
                Text(lang.pick("每周手动设置", "Manual Weekly Plan")).tag(SchoolScheduleSource.manual)
                Text(lang.pick("邮箱 AI 辅助", "AI Mail Assist")).tag(SchoolScheduleSource.mailAssisted)
            }
            .pickerStyle(.segmented)
        } header: {
            Text(lang.pick("时间规划", "Schedule Planning"))
        } footer: {
            Text(lang.pick(
                "AI 只能提取邮件里的明确日期和事实；所有结果先由家长确认。AI 不会猜上下学时间。",
                "AI only extracts explicit dates and facts. A parent confirms every result, and AI never guesses school hours."
            ))
        }
    }

    private var defaultTimeSection: some View {
        Section {
            DatePicker(
                lang.pick("默认上学时间", "Default Start"),
                selection: timeBinding(
                    get: { profile.defaultStartMinutes },
                    set: { profile.defaultStartMinutes = min($0, profile.defaultEndMinutes - 1) }
                ),
                displayedComponents: .hourAndMinute
            )
            DatePicker(
                lang.pick("默认放学时间", "Default End"),
                selection: timeBinding(
                    get: { profile.defaultEndMinutes },
                    set: { profile.defaultEndMinutes = max($0, profile.defaultStartMinutes + 1) }
                ),
                displayedComponents: .hourAndMinute
            )
        } header: {
            Text(lang.pick("邮件缺少时间时", "When Mail Has No Hours"))
        } footer: {
            Text(lang.pick(
                "邮件只说哪天上学、放假或提前放学，却没有完整时间时，学校日使用这里的家长确认时段；放假日全天不启用学校锁定。",
                "When mail names a school day, holiday, or early release without complete hours, school days use these parent-confirmed hours; holidays never activate the school restriction."
            ))
        }
    }

    private var weekdaySection: some View {
        Section {
            ForEach(profile.weekdayRules) { rule in
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(weekdayName(rule.weekday), isOn: ruleEnabledBinding(rule.weekday))
                    if rule.isEnabled {
                        HStack {
                            DatePicker(
                                lang.pick("开始", "Start"),
                                selection: ruleTimeBinding(rule.weekday, isStart: true),
                                displayedComponents: .hourAndMinute
                            )
                            DatePicker(
                                lang.pick("结束", "End"),
                                selection: ruleTimeBinding(rule.weekday, isStart: false),
                                displayedComponents: .hourAndMinute
                            )
                        }
                        .font(.caption)
                    }
                }
            }
        } header: {
            Text(lang.pick("每周上学日", "Weekly School Days"))
        }
    }

    private var exceptionSection: some View {
        Section {
            if profile.exceptions.isEmpty {
                Text(lang.pick("还没有放假或特殊上学日。", "No holidays or special school days yet."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(profile.exceptions.sorted { $0.dateKey < $1.dateKey }) { item in
                    HStack {
                        Image(systemName: item.kind == .holiday ? "sun.max.fill" : "calendar.badge.clock")
                            .foregroundStyle(item.kind == .holiday ? Color.orange : Color.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                            Text("\(item.dateKey) · \(exceptionDetail(item))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            profile.exceptions.removeAll { $0.id == item.id }
                            saveProfile()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        } header: {
            Text(lang.pick("日期例外", "Date Exceptions"))
        }
    }

    private var dynamicsSection: some View {
        Section {
            NavigationLink {
                SchoolDynamicsView(childID: selectedChildID)
            } label: {
                HStack {
                    Label(lang.pick("儿童学校动态", "Child School Updates"), systemImage: "book.pages")
                    Spacer()
                    Text("\(store.schoolDynamics(for: selectedChildID).count)")
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("school-mode-dynamics")
        } footer: {
            Text(lang.pick(
                "成绩、出勤和老师反馈只保存为本机摘要，可作为 AI 理解孩子的参考；家长邮箱原文不会保存。",
                "Grades, attendance, and teacher feedback are kept only as on-device summaries for AI context; the parent's email body is never retained."
            ))
        }
    }

    private var deviceSection: some View {
        Section {
            #if canImport(FamilyControls) && canImport(ManagedSettings)
            LabeledContent(lang.pick("系统授权", "System Authorization"), value: screenTime.authorizationState.label)
            LabeledContent(
                lang.pick("受控范围", "Controlled Scope"),
                value: lang.pick(
                    "\(screenTime.selectionCounts.applications) App · \(screenTime.selectionCounts.categories) 类别",
                    "\(screenTime.selectionCounts.applications) apps · \(screenTime.selectionCounts.categories) categories"
                )
            )
            if !screenTime.isChildFamilyAuthorizationReady {
                Button {
                    Task {
                        await screenTime.requestChildFamilyAuthorization()
                        synchronizeDeviceRule()
                    }
                } label: {
                    Label(lang.pick("请求儿童设备控制授权", "Authorize Child-Device Controls"), systemImage: "person.badge.key")
                }
            }
            Button {
                showsPicker = true
            } label: {
                Label(lang.pick("选择学校时段受控 App 与类别", "Choose Controlled Apps and Categories"), systemImage: "square.grid.3x3")
            }
            if let error = screenTime.schoolModeLastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if selectedChildID != store.activeChildId {
                Text(lang.pick(
                    "这份规则已保存，但当前手机绑定的是 \(store.child.name)，所以不会在本机执行。切换设备上的孩子身份后会自动同步对应规则。",
                    "This profile is saved, but this phone currently belongs to \(store.child.name), so it is not enforced here. The matching rules sync when the child profile on this device changes."
                ))
                .font(.caption)
                .foregroundStyle(.orange)
            }
            #else
            Text(lang.pick("当前系统不支持 FamilyControls。", "FamilyControls is unavailable on this system."))
            #endif
        } header: {
            Text(lang.pick("设备执行", "Device Enforcement"))
        } footer: {
            Text(lang.pick(
                "学校时段会遮挡家长选定的 App、类别和网站，并在时段结束后自动解除学校规则。章鱼老师、电话与系统紧急功能仍可使用；这是 Apple 允许的真实边界。",
                "During school hours, parent-selected apps, categories, and websites are shielded, then the school rule clears automatically. Octo Teacher, Phone, and emergency system features remain available; this is Apple's real boundary."
            ))
        }
    }

    private func reloadProfile() {
        profile = store.schoolModeProfile(for: selectedChildID)
    }

    private func saveProfile() {
        store.setSchoolModeProfile(profile)
        profile = store.schoolModeProfile(for: selectedChildID)
        synchronizeDeviceRule()
    }

    private func synchronizeDeviceRule() {
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        guard selectedChildID == store.activeChildId else { return }
        screenTime.synchronizeSchoolMode(profile: store.schoolModeProfile(for: selectedChildID))
        #endif
    }

    private func timeBinding(get: @escaping () -> Int, set: @escaping (Int) -> Void) -> Binding<Date> {
        Binding(
            get: { dateFromMinutes(get()) },
            set: { value in
                set(minutesFromDate(value))
                saveProfile()
            }
        )
    }

    private func ruleEnabledBinding(_ weekday: Int) -> Binding<Bool> {
        Binding(
            get: { profile.weekdayRules.first(where: { $0.weekday == weekday })?.isEnabled ?? false },
            set: { enabled in
                updateRule(weekday) { $0.isEnabled = enabled }
            }
        )
    }

    private func ruleTimeBinding(_ weekday: Int, isStart: Bool) -> Binding<Date> {
        Binding(
            get: {
                let rule = profile.weekdayRules.first(where: { $0.weekday == weekday })
                return dateFromMinutes(isStart ? (rule?.startMinutes ?? 480) : (rule?.endMinutes ?? 900))
            },
            set: { value in
                let minutes = minutesFromDate(value)
                updateRule(weekday) { rule in
                    if isStart {
                        rule.startMinutes = min(minutes, rule.endMinutes - 1)
                    } else {
                        rule.endMinutes = max(minutes, rule.startMinutes + 1)
                    }
                }
            }
        )
    }

    private func updateRule(_ weekday: Int, change: (inout SchoolWeekdayRule) -> Void) {
        guard let index = profile.weekdayRules.firstIndex(where: { $0.weekday == weekday }) else { return }
        change(&profile.weekdayRules[index])
        saveProfile()
    }

    private func dateFromMinutes(_ minutes: Int) -> Date {
        Calendar.current.date(byAdding: .minute, value: minutes, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    private func minutesFromDate(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private func weekdayName(_ weekday: Int) -> String {
        let chinese = ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let english = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return lang == .english ? english[weekday] : chinese[weekday]
    }

    private func exceptionDetail(_ item: SchoolCalendarException) -> String {
        if item.kind == .holiday { return lang.pick("全天放假", "Holiday") }
        let start = item.startMinutes ?? profile.defaultStartMinutes
        let end = item.endMinutes ?? profile.defaultEndMinutes
        return "\(clockText(start))–\(clockText(end))"
    }

    private func clockText(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

}

private struct SchoolDynamicsView: View {
    @Environment(LocalFamilyStore.self) private var store
    let childID: UUID

    private var lang: AppInterfaceLanguage { store.settings.resolvedParentInterfaceLanguage }

    var body: some View {
        List {
            let records = store.schoolDynamics(for: childID)
            if records.isEmpty {
                ContentUnavailableView(
                    lang.pick("还没有学校动态", "No School Updates Yet"),
                    systemImage: "building.columns",
                    description: Text(lang.pick("确认邮件识别结果后，结构化摘要会保存在这里。", "Confirmed structured summaries will appear here."))
                )
            } else {
                ForEach(records) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title).font(.headline)
                        Text(item.summary).font(.subheadline).foregroundStyle(.secondary)
                        HStack {
                            if let date = item.eventDateKey { Text(date) }
                            Spacer()
                            Text(item.createdAt.formatted(date: .abbreviated, time: .omitted))
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(lang.pick("儿童学校动态", "Child School Updates"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
