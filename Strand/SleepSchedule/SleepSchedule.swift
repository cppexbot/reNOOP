//  SleepSchedule.swift
//  NOOP · Sleep schedule — the strap alarm and the bedtime reminder read as the Health app's sleep
//  schedules: one card per group of days that share a wake time, bedtime = wake − sleep goal.
//
//  Pure: every figure the schedule page, its editor and the Sleep tab show comes from here, and the next
//  wake resolves through `AppModel.nextSmartAlarmDate`, the resolver `applySmartAlarm` arms the strap from.
//
//  Storage is unchanged. The base wake is `behavior.smartAlarmMinutes` (mirrored into
//  `windDown.wakeMinutes`, see `reconciledBaseWake`), the days are `behavior.smartAlarmWeekdays` (empty =
//  every day), a day with its own time is a `windDown.perDayWakeMinutes` override (#554 / #1864, which
//  re-times both the alarm and the reminder), and the sleep goal is `windDown.sleepNeedMinutes`.

import Foundation

struct SleepScheduleInputs: Equatable {
    /// `behavior.smartAlarmEnabled`.
    var alarmOn: Bool
    /// False for a WHOOP 5/MG without Experimental: `BLEManager.armStrapAlarm` does not arm it (#864).
    var alarmWillArm: Bool
    /// `behavior.smartAlarmMinutes`: the wake time of every day without one of its own.
    var baseWake: Int
    /// `behavior.smartAlarmWeekdays`, Calendar numbering (1 = Sun … 7 = Sat). Empty = every day.
    var alarmDays: Set<Int>
    /// `WindDownNudge.perDayWakeOverrides`.
    var overrides: [Int: Int]
    /// `WindDownNudge.sleepNeedMinutes`.
    var sleepGoal: Int
}

/// One card of the full schedule.
struct SleepScheduleEntry: Identifiable, Equatable {
    enum Kind: Equatable { case base, ownTime }
    let kind: Kind
    /// Calendar weekdays, Monday first.
    let days: [Int]
    let wake: Int
    let bed: Int
    /// Whether the strap alarm goes off on these days ("Wake Up" vs "Wake Up — No Alarm").
    let alarm: Bool

    var id: String { "\(kind == .base ? "base" : "own")-\(days.map(String.init).joined(separator: ","))" }
}

/// The next wake, with the evening before it.
struct SleepNextWake: Equatable {
    let wake: Date
    let bed: Date
    /// The strap alarm is on and will arm, so this wake is an alarm and may count down.
    let armed: Bool
}

enum SleepSchedule {
    static let day = 24 * 60
    /// Calendar weekdays laid out Monday first.
    static let weekOrder = [2, 3, 4, 5, 6, 7, 1]
    /// `WindDownNudge`'s clamp on the sleep goal.
    static let goalRange = (5 * 60)...(11 * 60)

    static func wrap(_ minutes: Int) -> Int { ((minutes % day) + day) % day }

    /// The days the alarm may fire on, with "every day" spelled out.
    static func effectiveAlarmDays(_ days: Set<Int>) -> Set<Int> {
        let valid = days.filter { (1...7).contains($0) }
        return valid.isEmpty ? Set(1...7) : valid
    }

    // MARK: - Cards

    /// The base card first (the alarm days without a time of their own), then one card per group of days
    /// sharing their own time and alarm state, ordered by their first day. Days neither on the alarm nor
    /// holding a time of their own have no card: nothing wakes anybody on them.
    static func entries(_ inputs: SleepScheduleInputs) -> [SleepScheduleEntry] {
        let alarmDays = effectiveAlarmDays(inputs.alarmDays)
        let own = inputs.overrides.filter { (1...7).contains($0.key) && (0..<day).contains($0.value) }
        let sounding = inputs.alarmOn && inputs.alarmWillArm
        func entry(_ kind: SleepScheduleEntry.Kind, _ days: [Int], wake: Int, alarm: Bool) -> SleepScheduleEntry {
            SleepScheduleEntry(kind: kind, days: days, wake: wake, bed: wrap(wake - inputs.sleepGoal), alarm: alarm)
        }
        var out = [entry(.base, weekOrder.filter { alarmDays.contains($0) && own[$0] == nil },
                         wake: inputs.baseWake, alarm: sounding)]
        struct Key: Hashable { let wake: Int; let alarm: Bool }
        var groups: [Key: [Int]] = [:]
        for d in weekOrder { if let w = own[d] { groups[Key(wake: w, alarm: alarmDays.contains(d)), default: []].append(d) } }
        out += groups
            .map { entry(.ownTime, $0.value, wake: $0.key.wake, alarm: sounding && $0.key.alarm) }
            .sorted { (weekOrder.firstIndex(of: $0.days[0]) ?? 0) < (weekOrder.firstIndex(of: $1.days[0]) ?? 0) }
        return out
    }

    // MARK: - Next wake (the one funnel)

    /// The next wake the schedule holds, resolved from `now` by the resolver `applySmartAlarm` arms the
    /// strap from, so a day with its own time resolves to THAT time. Every readout of the next wake takes
    /// its date, bedtime and countdown from one call with one `now`.
    static func nextWake(_ inputs: SleepScheduleInputs, from now: Date, calendar: Calendar = .current) -> SleepNextWake? {
        guard let wake = AppModel.nextSmartAlarmDate(minutes: inputs.baseWake, weekdays: inputs.alarmDays,
                                                     overrides: inputs.overrides, from: now, calendar: calendar)
        else { return nil }
        return SleepNextWake(wake: wake, bed: wake.addingTimeInterval(-Double(inputs.sleepGoal) * 60),
                             armed: inputs.alarmOn && inputs.alarmWillArm)
    }

    /// "7 hr 12 min" until an ARMED wake; nil for one that will not sound (a countdown is a promise).
    static func countdown(_ next: SleepNextWake?, from now: Date, locale: Locale) -> String? {
        guard let next, next.armed else { return nil }
        let seconds = next.wake.timeIntervalSince(now)
        guard seconds >= 60 else { return String(localized: "Alarm in less than a minute") }
        let formatter = DateComponentsFormatter()
        var cal = Calendar.current
        cal.locale = locale
        formatter.calendar = cal
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.zeroFormattingBehavior = .dropAll
        formatter.maximumUnitCount = 2
        guard let span = formatter.string(from: seconds), !span.isEmpty else { return nil }
        return String(localized: "Alarm in \(span)")
    }

    // MARK: - One wake time

    /// The one base wake time. The alarm's time and the reminder's "usual wake" were two settings shown
    /// as two times (#2353); the schedule shows one, so they are written together. When they already
    /// differ, the one in use wins: the alarm's when it is on, else the reminder's when that is on.
    static func reconciledBaseWake(alarmOn: Bool, alarmWake: Int, reminderOn: Bool, reminderWake: Int) -> Int {
        if alarmOn || !reminderOn { return alarmWake }
        return reminderWake
    }

    // MARK: - Weekdays

    /// A day reads as "on" when the set is empty (= every day) or explicitly contains it.
    static func weekdayIsSelected(_ dow: Int, in days: Set<Int>) -> Bool {
        days.isEmpty || days.contains(dow)
    }

    /// An alarm-day set written back: all seven collapse to empty, the stored spelling of "every day".
    static func normalizedAlarmDays(_ days: Set<Int>) -> Set<Int> {
        let valid = days.filter { (1...7).contains($0) }
        return valid.count == 7 ? [] : valid
    }

    /// "Every day", "Weekdays", "Weekends", else "Mon, Wed".
    static func weekdaySummary(_ days: Set<Int>) -> String {
        if days.isEmpty || days.count == 7 { return String(localized: "Every day") }
        if days == Set(2...6) { return String(localized: "Weekdays") }
        if days == Set([1, 7]) { return String(localized: "Weekends") }
        return weekOrder.filter { days.contains($0) }.map { weekdayShort($0) }.joined(separator: ", ")
    }

    static func weekdayShort(_ dow: Int) -> String {
        switch dow {
        case 1: return String(localized: "Sun")
        case 2: return String(localized: "Mon")
        case 3: return String(localized: "Tue")
        case 4: return String(localized: "Wed")
        case 5: return String(localized: "Thu")
        case 6: return String(localized: "Fri")
        case 7: return String(localized: "Sat")
        default: return "?"
        }
    }

    /// The one-letter day circle ("M", "T" … or "П", "В" …), from the locale's own symbols.
    static func weekdayLetter(_ dow: Int, locale: Locale) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = locale
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        return (1...7).contains(dow) ? symbols[dow - 1].uppercased(with: locale) : "?"
    }

    static func weekdayName(_ dow: Int, locale: Locale) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = locale
        return (1...7).contains(dow) ? cal.standaloneWeekdaySymbols[dow - 1] : "?"
    }

    // MARK: - Formatting

    /// A minute of the day as the reader's clock shows it.
    static func clock(_ minutes: Int, locale: Locale) -> String {
        var c = DateComponents()
        c.hour = wrap(minutes) / 60
        c.minute = wrap(minutes) % 60
        return clock(Calendar.current.date(from: c) ?? Date(), locale: locale)
    }

    /// A time as Health prints it: two-digit hours on a 24-hour clock ("06:30"), the locale's 12-hour
    /// form where that is the convention.
    static func clock(_ date: Date, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("jjmm")
        if formatter.dateFormat.contains("H"), !formatter.dateFormat.contains("HH") {
            formatter.dateFormat = formatter.dateFormat.replacingOccurrences(of: "H", with: "HH")
        }
        return formatter.string(from: date)
    }

    /// "8 hr" / "8 hr 30 min".
    static func duration(_ minutes: Int, locale: Locale) -> String {
        let formatter = DateComponentsFormatter()
        var cal = Calendar.current
        cal.locale = locale
        formatter.calendar = cal
        formatter.unitsStyle = .short
        formatter.allowedUnits = [.hour, .minute]
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: Double(minutes) * 60) ?? ""
    }
}

// MARK: - Editing

/// What the schedule editor hands back.
struct SleepScheduleEdit: Equatable {
    /// The card being edited; nil adds a new schedule with its own time.
    var original: SleepScheduleEntry?
    var days: Set<Int>
    var bed: Int
    var wake: Int
    /// Own-time schedules only: whether the strap alarm goes off on their days.
    var alarm: Bool
    var delete = false

    var isBase: Bool { original?.kind == .base }
}

/// The stored settings an edit resolves to.
struct SleepScheduleStored: Equatable {
    var baseWake: Int
    var alarmDays: Set<Int>
    var overrides: [Int: Int]
    var sleepGoal: Int
}

extension SleepSchedule {
    /// The sleep goal a bedtime and wake span, clamped as `WindDownNudge` stores it.
    static func goal(bed: Int, wake: Int) -> Int {
        min(max(wrap(wake - bed), goalRange.lowerBound), goalRange.upperBound)
    }

    /// The settings after `edit`, or nil when the result has no spelling: an alarm-day set cannot be
    /// empty, since the empty set is how "every day" is stored.
    ///
    /// - Base card: its days become the alarm days (own-time days that ring keep ringing), a day picked
    ///   here drops its own time, and its wake is the base wake.
    /// - Own-time card: its days take its wake as their own time and join (or leave) the alarm days; a
    ///   day unpicked or deleted drops its own time and falls back to the base card.
    /// Either way the bedtime sets the one sleep goal every card shares.
    static func applying(_ edit: SleepScheduleEdit, to inputs: SleepScheduleInputs) -> SleepScheduleStored? {
        let alarmDays = effectiveAlarmDays(inputs.alarmDays)
        var overrides = inputs.overrides
        var baseWake = inputs.baseWake
        var newAlarm = alarmDays
        let picked: Set<Int> = edit.delete ? [] : edit.days.filter { (1...7).contains($0) }
        if edit.isBase {
            guard !picked.isEmpty else { return nil }
            let ringingOwn = alarmDays.intersection(overrides.keys).subtracting(picked)
            newAlarm = picked.union(ringingOwn)
            for d in picked { overrides[d] = nil }
            baseWake = wrap(edit.wake)
        } else {
            for d in edit.original?.days ?? [] where !picked.contains(d) { overrides[d] = nil }
            for d in picked { overrides[d] = wrap(edit.wake) }
            if !edit.delete {
                newAlarm = edit.alarm ? alarmDays.union(picked) : alarmDays.subtracting(picked)
            }
            guard !newAlarm.isEmpty else { return nil }
        }
        let goal = edit.delete ? inputs.sleepGoal : goal(bed: edit.bed, wake: edit.wake)
        return SleepScheduleStored(baseWake: baseWake, alarmDays: normalizedAlarmDays(newAlarm),
                                   overrides: overrides, sleepGoal: goal)
    }
}
