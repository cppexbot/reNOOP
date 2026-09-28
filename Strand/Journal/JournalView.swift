//  JournalView.swift
//  NOOP · Journal — habits, mood and caffeine for one day, laid out as Health's Medications log.
//
//  Health iOS 26 Medications: the day's name, a strip of days with a filled circle per day (how much
//  of it was logged), "Log" cards with a "+", then what was logged. Here the day strip runs from
//  six days back to tomorrow (journal answers feed the effect ranker, so backfill is bounded, #656);
//  habits answer in a sheet, mood and caffeine log straight from their row's "+" menu.
//
//  Writes go through the same Repository calls the old Insights journal used, under the native
//  `noop-journal` source, so imported WHOOP rows are never touched.

import SwiftUI
import StrandDesign
import WhoopStore

struct JournalView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    @StateObject private var catalog = JournalCatalogStore()
    @ObservedObject private var caffeine = CaffeineLogStore.shared

    /// Days back from today; -1 is tomorrow.
    @State private var offset = 0
    /// Imported ∪ native answers, every day (native wins per day + question).
    @State private var entries: [JournalEntry] = []
    @State private var importedQuestions: [String] = []
    /// The selected day's native answers, which the habits sheet edits.
    @State private var answers: [String: Bool] = [:]
    @State private var numeric: [String: Double] = [:]
    /// Mood (1–5) by day key.
    @State private var moods: [String: Int] = [:]
    @State private var showHabits = false

    @Environment(\.dynamicTypeSize) private var dts
    @ScaledMetric(relativeTo: .body) private var iconColumn: CGFloat = 26
    @ScaledMetric(relativeTo: .body) private var loggedIconSize: CGFloat = 18

    private static let offsets: [Int] = Array((-1...6).reversed())
    private let tint = StrandPalette.healthMind

    private var calendar: Calendar { .current }
    private var locale: Locale { AppLanguage.activeLocale }

    private func date(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
    }
    private func dayKey(_ offset: Int) -> String { Repository.localDayKey(date(offset)) }
    private var selectedKey: String { dayKey(offset) }

    private var items: [JournalCatalogItem] {
        catalog.resolvedItems(imported: importedQuestions, includeHidden: false)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: dayTitle)
                    .font(StrandFont.pro(20, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .frame(maxWidth: .infinity)
                dayStrip
                    .padding(.bottom, 8)
                sectionHeader("To Log")
                logCards
                if !loggedRows.isEmpty {
                    loggedCard
                        .padding(.top, NoopMetrics.space2)
                }
            }
            .padding(.horizontal, NoopMetrics.screenHPadding)
            .padding(.top, NoopMetrics.space2)
            .padding(.bottom, NoopMetrics.space8 + NoopMetrics.tabBarClearance)
            #if os(macOS)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            #endif
        }
        .background(StrandPalette.plainPage.ignoresSafeArea())
        .navigationTitle(Text("Journal"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                addMenu { Image(systemName: "plus") }.barGlyph()
            }
        }
        .sheet(isPresented: $showHabits, onDismiss: { Task { await load() } }) {
            JournalHabitsSheet(catalog: catalog, items: { items }, day: selectedKey,
                               title: dayTitle, answers: $answers, numeric: $numeric)
        }
        .task(id: "\(repo.refreshSeq)|\(offset)") { await load() }
        .onAppear {
            // #656: the Summary's journal widget opens a specific day.
            if let day = router.pendingJournalDayOffset {
                offset = Self.offsets.contains(day) ? day : 0
                router.pendingJournalDayOffset = nil
            }
        }
    }

    // MARK: - Day

    /// "Today, 27 September" / "Yesterday, …" / "Thursday, 24 September".
    private var dayTitle: String {
        let d = date(offset)
        let dayMonth = d.formatted(.dateTime.day().month(.wide).locale(locale))
        switch offset {
        case -1: return String(localized: "Tomorrow") + ", " + dayMonth
        case 0:  return String(localized: "Today") + ", " + dayMonth
        case 1:  return String(localized: "Yesterday") + ", " + dayMonth
        default: return d.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale)).capitalizedFirstLetter
        }
    }

    private var dayStrip: some View {
        HStack(spacing: 0) {
            ForEach(Self.offsets, id: \.self) { off in
                Button { offset = off } label: { dayColumn(off) }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
            }
        }
        // Eight fixed circles across the row: the letters follow Dynamic Type only as far as a circle holds one.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func dayColumn(_ off: Int) -> some View {
        let selected = off == offset
        let letter = String(date(off).formatted(.dateTime.weekday(.narrow).locale(locale)))
        return VStack(spacing: 6) {
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 9))
                .foregroundStyle(selected ? StrandPalette.textPrimary : .clear)
            Text(verbatim: letter)
                .font(StrandFont.pro(13, weight: .semibold))
                .foregroundStyle(selected ? StrandPalette.summaryCard : StrandPalette.textSecondary)
                .frame(width: 22, height: 22)
                .background(selected ? StrandPalette.textPrimary : .clear, in: Circle())
            ZStack {
                Circle().fill(StrandPalette.textTertiary.opacity(0.18))
                Circle().fill(tint)
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: 36 * fraction(dayKey(off)))
                    }
            }
            .frame(width: 36, height: 36)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: date(off).formatted(.dateTime.weekday(.wide).day().month().locale(locale))))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// How much of a day's journal is filled in: answered habits plus mood, over the habit list plus one.
    private func fraction(_ day: String) -> CGFloat {
        let answered = Set(entries.filter { $0.day == day }.map(\.question)).count + (moods[day] == nil ? 0 : 1)
        guard answered > 0 else { return 0 }
        return CGFloat(min(1, Double(answered) / Double(max(items.count + 1, 1))))
    }

    // MARK: - To Log

    private var logCards: some View {
        VStack(spacing: 10) {
            logCard(icon: "checklist", title: String(localized: "Habits")) {
                Button { showHabits = true } label: { plusGlyph }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Habits"))
            }
            logCard(icon: "face.smiling", title: String(localized: "Mood")) {
                moodMenu { plusGlyph }
            }
            if offset >= 0 {
                logCard(icon: "cup.and.saucer.fill", title: String(localized: "Caffeine")) {
                    caffeineMenu { plusGlyph }
                }
            }
        }
    }

    /// One tinted "Log" card, as Health's scheduled-dose card: title on the left, "+" on the right. What was
    /// logged shows once, under "Logged", not again here.
    private func logCard<Trailing: View>(icon: String, title: String,
                                         @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(StrandFont.pro(17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: iconColumn)
            Text(verbatim: title)
                .font(StrandFont.pro(17))
                .foregroundStyle(StrandPalette.textPrimary)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: SummaryCard<EmptyView>.radius, style: .continuous))
    }

    private var plusGlyph: some View {
        Image(systemName: "plus")
            .font(StrandFont.pro(20, weight: .medium))
            .foregroundStyle(tint)
            .frame(minWidth: 32, minHeight: 32)
            .contentShape(Rectangle())
    }

    private func addMenu<L: View>(@ViewBuilder label: () -> L) -> some View {
        Menu {
            Button { showHabits = true } label: { Label("Habits", systemImage: "checklist") }
            Menu {
                moodButtons
            } label: { Label("Mood", systemImage: "face.smiling") }
            if offset >= 0 {
                Menu {
                    caffeineButtons
                } label: { Label("Caffeine", systemImage: "cup.and.saucer.fill") }
            }
        } label: { label() }
    }

    private func moodMenu<L: View>(@ViewBuilder label: () -> L) -> some View {
        Menu { moodButtons } label: { label() }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel(Text("Mood"))
    }

    @ViewBuilder private var moodButtons: some View {
        ForEach(MoodStore.scale.reversed(), id: \.self) { value in
            Button {
                let day = selectedKey
                moods[day] = value
                Task { await repo.saveMood(day: day, value: value) }
            } label: {
                Text(verbatim: "\(MoodStore.face(for: value))  \(MoodStore.label(for: value))")
            }
        }
    }

    private func caffeineMenu<L: View>(@ViewBuilder label: () -> L) -> some View {
        Menu { caffeineButtons } label: { label() }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel(Text("Caffeine"))
    }

    /// Today: now or a few hours ago. An earlier day: that day at noon, the time being unknown.
    @ViewBuilder private var caffeineButtons: some View {
        if offset == 0 {
            ForEach([0, 1, 2, 3], id: \.self) { h in
                Button {
                    caffeine.log(at: Date().addingTimeInterval(-Double(h) * 3_600))
                } label: {
                    Text(h == 0 ? String(localized: "Now") : String(localized: "\(h)h ago"))
                }
            }
        } else {
            Button {
                let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date(offset)) ?? date(offset)
                caffeine.log(at: noon)
            } label: { Text("Add") }
        }
    }

    // MARK: - Logged

    private struct LoggedRow: Identifiable {
        let id: String
        let title: String
        let value: String
        let done: Bool
        let remove: (() -> Void)?
    }

    private func intakes(on day: String) -> [CaffeineIntake] {
        caffeine.intakes.filter { Repository.localDayKey($0.at) == day }.sorted { $0.at < $1.at }
    }

    private var loggedRows: [LoggedRow] {
        let day = selectedKey
        var rows: [LoggedRow] = []
        if let mood = moods[day] {
            rows.append(LoggedRow(id: "mood", title: String(localized: "Mood"),
                                  value: "\(MoodStore.face(for: mood)) \(MoodStore.label(for: mood))",
                                  done: true, remove: nil))
        }
        let names = Dictionary(items.map { ($0.canonical, $0) }, uniquingKeysWith: { a, _ in a })
        for e in entries.filter({ $0.day == day }).sorted(by: { $0.question < $1.question }) {
            let item = names[e.question]
            let value: String
            if let v = e.numericValue {
                let n = v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
                value = [n, item?.kind.unitLabel].compactMap { $0 }.joined(separator: " ")
            } else {
                value = e.answeredYes ? String(localized: "Yes") : String(localized: "No")
            }
            // Only the native row can be cleared; an imported answer belongs to its export.
            let native = answers[e.question] != nil || numeric[e.question] != nil
            let question = e.question
            rows.append(LoggedRow(id: "j:" + question, title: item?.display ?? question, value: value,
                                  done: e.answeredYes,
                                  remove: native ? {
                                      Task { await repo.clearJournalAnswer(day: day, question: question); await load() }
                                  } : nil))
        }
        for intake in intakes(on: day) {
            let time = AppClock.hourMinuteFormatter().string(from: intake.at)
            let mg = intake.mg.map { "\(Int($0.rounded())) " + String(localized: "mg") }
            rows.append(LoggedRow(id: "c:" + intake.id.uuidString, title: String(localized: "Caffeine"),
                                  value: [mg, time].compactMap { $0 }.joined(separator: " · "),
                                  done: true,
                                  remove: intake.isImported ? nil : { caffeine.remove(intake.id) }))
        }
        return rows
    }

    /// Health's "Logged" card: grey on the white page, its title inside above a hairline.
    private var loggedCard: some View {
        let rows = loggedRows
        return VStack(alignment: .leading, spacing: 0) {
            Text("Logged")
                .font(StrandFont.pro(17, weight: .semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .padding(.vertical, 12)
                .accessibilityAddTraits(.isHeader)
            Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                // The value moves under the title at accessibility sizes.
                let stacked = dts.isAccessibilitySize
                let layout = stacked
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                    : AnyLayout(HStackLayout(spacing: 10))
                layout {
                    HStack(spacing: 10) {
                        Image(systemName: row.done ? "checkmark.circle.fill" : "minus.circle.fill")
                            .font(.system(size: loggedIconSize))
                            .foregroundStyle(row.done ? tint : StrandPalette.textTertiary)
                        Text(verbatim: row.title)
                            .font(StrandFont.pro(17))
                            .foregroundStyle(StrandPalette.textPrimary)
                            .lineLimit(stacked ? nil : 1)
                    }
                    if !stacked { Spacer(minLength: 8) }
                    Text(verbatim: row.value)
                        .font(StrandFont.pro(17))
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(stacked ? nil : 1)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .contextMenu {
                    if let remove = row.remove {
                        Button(role: .destructive, action: remove) { Label("Delete", systemImage: "trash") }
                    }
                }
                if i < rows.count - 1 {
                    Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                        .padding(.leading, 28)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .background(StrandPalette.plainPageCard,
                    in: RoundedRectangle(cornerRadius: SummaryCard<EmptyView>.radius, style: .continuous))
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(StrandFont.pro(22, weight: .bold))
            .foregroundStyle(StrandPalette.textPrimary)
            .padding(.horizontal, 4)
            .padding(.top, NoopMetrics.space2)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Load

    private func load() async {
        let all = await repo.journalEntries(days: 14)
        let imported = await repo.importedJournalEntries()
        let day = selectedKey
        let nativeAnswers = await repo.nativeJournalAnswers(day: day)
        let nativeNumeric = await repo.nativeJournalNumeric(day: day)
        var moodByDay: [String: Int] = [:]
        for off in Self.offsets {
            let key = dayKey(off)
            if let m = await repo.mood(day: key) { moodByDay[key] = m }
        }
        entries = all
        importedQuestions = NSOrderedSet(array: imported.map(\.question)).array as? [String] ?? []
        answers = nativeAnswers
        numeric = nativeNumeric
        moods = moodByDay
    }
}

private extension String {
    /// "четверг, 24 сентября" → "Четверг, 24 сентября" (weekday names are lowercase in many locales).
    var capitalizedFirstLetter: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Habits sheet

/// The day's habits as a native form, one row per journal item: Yes/No or a number. Items can be added,
/// renamed, regrouped, switched between Yes/No and a number, and hidden (built-in) or deleted (custom).
struct JournalHabitsSheet: View {
    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var catalog: JournalCatalogStore
    let items: () -> [JournalCatalogItem]
    let day: String
    let title: String
    @Binding var answers: [String: Bool]
    @Binding var numeric: [String: Double]

    @State private var draft = ""
    @ScaledMetric(relativeTo: .body) private var fieldWidth: CGFloat = 72
    @State private var draftNumeric = false
    @State private var renaming: JournalCatalogItem?
    @State private var renameDraft = ""

    var body: some View {
        NavigationStack {
            Form {
                ForEach(JournalGroup.displayOrder, id: \.self) { group in
                    let rows = items().filter { $0.group == group }
                        .sorted { ($0.sortIndex, $0.display) < ($1.sortIndex, $1.display) }
                    if !rows.isEmpty {
                        Section(group.title) {
                            ForEach(rows) { item in row(item) }
                        }
                    }
                }
                Section {
                    TextField("New Item", text: $draft)
                        .onSubmit(add)
                    Picker("Type", selection: $draftNumeric) {
                        Text("Yes/No").tag(false)
                        Text("Number").tag(true)
                    }
                    Button("Add", action: add)
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle(Text("Habits"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    SheetConfirmButton(tint: StrandPalette.settingsBlue) { dismiss() }
                }
            }
            .alert("Rename…", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("", text: $renameDraft)
                Button("Cancel", role: .cancel) { renaming = nil }
                Button("Done") {
                    if let item = renaming { catalog.rename(item.canonical, to: renameDraft) }
                    renaming = nil
                }
            }
        }
    }

    @ViewBuilder private func row(_ item: JournalCatalogItem) -> some View {
        HStack {
            Text(verbatim: item.display)
            Spacer(minLength: 8)
            if item.kind.isNumeric {
                numericField(item)
            } else {
                answerButton("Yes", item: item, value: true)
                answerButton("No", item: item, value: false)
            }
        }
        .contextMenu {
            Button("Rename…") {
                renameDraft = item.displayName ?? item.canonical
                renaming = item
            }
            Menu("Group") {
                ForEach(JournalGroup.displayOrder, id: \.self) { g in
                    Button(g.title) { catalog.setGroup(item.canonical, to: g) }
                }
            }
            if item.kind.isNumeric {
                Button("Change to Yes/No") { catalog.setKind(item.canonical, to: .bool) }
            } else {
                Button("Change to Number") { catalog.setKind(item.canonical, to: .numeric(unitLabel: nil)) }
            }
            Button(role: .destructive) { catalog.remove(item.canonical) } label: {
                Text(item.custom ? "Delete" : "Hide")
            }
        }
    }

    /// Tri-state, as before: tapping the chosen answer again clears it.
    private func answerButton(_ label: LocalizedStringKey, item: JournalCatalogItem, value: Bool) -> some View {
        let selected = answers[item.canonical] == value
        return Button {
            let q = item.canonical
            if selected {
                answers[q] = nil
                Task { await repo.clearJournalAnswer(day: day, question: q) }
            } else {
                answers[q] = value
                Task { await repo.saveJournalAnswer(day: day, question: q, answeredYes: value) }
            }
        } label: {
            Text(label)
                .font(StrandFont.pro(15, weight: .semibold))
                .foregroundStyle(selected ? StrandPalette.summaryCard : StrandPalette.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(selected ? StrandPalette.healthMindText : StrandPalette.textTertiary.opacity(0.15),
                            in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func numericField(_ item: JournalCatalogItem) -> some View {
        let q = item.canonical
        let binding = Binding<Double?>(
            get: { numeric[q] },
            set: { v in
                numeric[q] = v
                Task {
                    if let v { await repo.saveJournalNumeric(day: day, question: q, value: v) }
                    else { await repo.clearJournalAnswer(day: day, question: q) }
                }
            })
        return HStack(spacing: 4) {
            TextField("—", value: binding, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: fieldWidth)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            if let unit = item.kind.unitLabel, !unit.isEmpty {
                Text(verbatim: unit).foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    private func add() {
        let t = draft.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        catalog.addCustom(t, kind: draftNumeric ? .numeric(unitLabel: nil) : .bool, group: .other)
        draft = ""
    }
}
