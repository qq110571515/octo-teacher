import Charts
import SwiftUI

/// 家长端任务完成报表：每个孩子今天/本周/本月的完成情况，按任务类型柱状图。
struct ParentTaskStatsView: View {
    @Environment(LocalFamilyStore.self) private var store

    @State private var range: LocalFamilyStore.StatsRange = .week

    var body: some View {
        List {
            Section {
                Picker("时间范围", selection: $range) {
                    ForEach(LocalFamilyStore.StatsRange.allCases, id: \.self) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }

            ForEach(store.children) { member in
                let stats = store.taskStats(for: member.id, range: range)
                Section {
                    if stats.isEmpty {
                        Text("\(range.label)还没有布置任务。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        let done = stats.reduce(0) { $0 + $1.done }
                        let total = stats.reduce(0) { $0 + $1.total }
                        HStack {
                            Text("完成 \(done) / \(total)")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(total > 0 ? "\(done * 100 / total)%" : "—")
                                .font(.subheadline)
                                .foregroundStyle(done == total && total > 0 ? .green : .secondary)
                        }
                        Chart {
                            ForEach(stats, id: \.category) { item in
                                BarMark(
                                    x: .value("类别", item.category.label),
                                    y: .value("布置", item.total)
                                )
                                .foregroundStyle(Color.gray.opacity(0.3))
                                BarMark(
                                    x: .value("类别", item.category.label),
                                    y: .value("完成", item.done)
                                )
                                .foregroundStyle(Color.green)
                            }
                        }
                        .frame(height: 180)
                        .chartYAxis {
                            AxisMarks(values: .automatic(desiredCount: 4))
                        }
                        Text("绿色 = 已完成，灰色 = 布置总数")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("\(member.name)（\(range.label)）")
                }
            }
        }
        .navigationTitle("任务完成报表")
        .navigationBarTitleDisplayMode(.inline)
    }
}
