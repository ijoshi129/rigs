import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(Switch2Controller.self) private var rig
    @AppStorage(Prefs.units) private var units: Units = .f
    @State private var confirmClear = false

    var body: some View {
        let entries = model.log.entries
        let cal = Calendar.current
        let today = entries.filter { cal.isDateInToday($0.start) }
        let targets = entries.compactMap(\.targetF).sorted()
        let usual = targets.isEmpty ? nil : targets[targets.count / 2]
        let days = (0..<7).map { cal.date(byAdding: .day, value: $0 - 6, to: .now)! }
        let counts = days.map { d in entries.filter { cal.isDate($0.start, inSameDayAs: d) }.count }
        let groups = Dictionary(grouping: entries) { cal.startOfDay(for: $0.start) }.sorted { $0.key > $1.key }

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: "History", subtitle: "Kept on this phone only")

                HStack(spacing: 10) {
                    tile("\(today.count)", "today")
                    tile(usual.map { "\(formatTemp($0, units))°" } ?? "—", "usual")
                    tile(rig.state.analytics.totalHeatingCycles.map { $0.formatted() } ?? "—", "on the rig")
                }

                HStack {
                    Text("This week")
                    Spacer()
                    Text("\(counts.reduce(0, +)) sessions").monospacedDigit()
                }
                .font(.geist(13)).foregroundStyle(Theme.ink2).padding(.top, 22).padding(.horizontal, 4)

                let maxCount = max(1, counts.max() ?? 1)
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(Array(counts.enumerated()), id: \.offset) { i, c in
                        VStack(spacing: 6) {
                            Rectangle()
                                .fill(i == 6 ? Theme.ink : Theme.line)
                                .frame(height: max(6, CGFloat(c) / CGFloat(maxCount) * 60))
                            Text(days[i].formatted(.dateTime.weekday(.narrow))).font(.geist(11)).foregroundStyle(Theme.ink3)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 84, alignment: .bottom)
                .padding(.top, 10)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Sessions per day this week: \(counts.map(String.init).joined(separator: ", "))")

                if entries.isEmpty {
                    Surface {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No sessions yet").font(.geist(15, .medium))
                            Text("Each heat cycle you run from here gets logged, with its peak temperature.").font(.geist(13)).foregroundStyle(Theme.ink2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 18)
                    }
                    .padding(.top, 24)
                } else {
                    ForEach(groups, id: \.key) { day, items in
                        SectionLabel(cal.isDateInToday(day) ? "Today" : day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        Surface {
                            ForEach(Array(items.enumerated()), id: \.element.id) { i, e in
                                HStack(spacing: 12) {
                                    Text(e.start.formatted(date: .omitted, time: .shortened)).font(.geist(13)).foregroundStyle(Theme.ink2).frame(width: 66, alignment: .leading)
                                    Text(e.targetF.map { "\(formatTemp($0, units))°" } ?? "—").font(.geist(24, .light)).monospacedDigit().frame(width: 64, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(e.profile ?? "Session").font(.geist(15))
                                        Text([e.holdSeconds.map { "\($0) s hold" }, e.peakF > 0 ? "peaked \(formatTemp(e.peakF, units))°" : nil, e.extended ? "extended" : nil].compactMap { $0 }.joined(separator: " · "))
                                            .font(.geist(12)).foregroundStyle(Theme.ink2)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 12)
                                .overlay(alignment: .bottom) { if i < items.count - 1 { Theme.line.frame(height: 1) } }
                            }
                        }
                    }
                    Button("Clear history") { confirmClear = true }
                        .font(.geist(13)).foregroundStyle(Theme.ink2).underline().padding(.top, 22).padding(.horizontal, 4)
                }

                Text("The rig's lifetime counter is read from the device. The session log is yours and never leaves the phone.")
                    .font(.geist(12)).foregroundStyle(Theme.ink3).padding(.top, 18).padding(.horizontal, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 100)
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Clear the whole history on this phone?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear history", role: .destructive) { model.log.clear() }
        }
    }

    private func tile(_ n: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(n).font(.geist(40, .light)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.geist(12)).foregroundStyle(Theme.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 14)
        .background(Theme.surface)
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
    }
}
