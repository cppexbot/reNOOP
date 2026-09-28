//  SystemWakeAlarm.swift
//  NOOP · the phone's backup to the strap's silent wake: a system alarm, as the Clock app sets one (AL-1).
//  AlarmKit rings through Silent mode and the Sleep Focus with the system's full-screen Stop, which a
//  notification cannot. iOS 26+; the caller falls back to a time-sensitive notification where AlarmKit is
//  missing or refused.

#if os(iOS) && canImport(AlarmKit)
import AlarmKit
import Foundation
import StrandDesign
import SwiftUI

@available(iOS 26.0, *)
enum SystemWakeAlarm {
    struct Metadata: AlarmMetadata {}

    /// The ids NOOP scheduled, so a re-arm or disarm cancels exactly its own alarms.
    private static let idsKey = "alarm.systemWakeAlarmIds"

    /// Schedules one weekly alarm per distinct wake time (Calendar weekdays 1 = Sunday … 7 = Saturday;
    /// an empty set = every day). Returns false when AlarmKit is not authorized, so the caller keeps the
    /// notification backup instead. Permission is asked only when `mayAsk` (the person just set the alarm).
    static func schedule(minutes: Int, weekdays: Set<Int>, overrides: [Int: Int], mayAsk: Bool) async -> Bool {
        let manager = AlarmManager.shared
        var state = manager.authorizationState
        if state == .notDetermined && mayAsk {
            state = (try? await manager.requestAuthorization()) ?? .denied
        }
        guard state == .authorized else { return false }
        cancelAll()

        let days = weekdays.isEmpty ? Set(1...7) : weekdays.filter { (1...7).contains($0) }
        var byTime: [Int: [Locale.Weekday]] = [:]
        for day in days.sorted() {
            guard let weekday = localeWeekday(day) else { continue }
            byTime[overrides[day] ?? minutes, default: []].append(weekday)
        }

        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource("schedule.wake", defaultValue: "Wake Up"),
            stopButton: AlarmButton(text: LocalizedStringResource("Stop"), textColor: .white,
                                    systemImageName: "stop.fill"))
        let attributes = AlarmAttributes<Metadata>(presentation: AlarmPresentation(alert: alert),
                                                   tintColor: StrandPalette.sleepSchedule)
        var ids: [String] = []
        for (minute, weekdays) in byTime {
            let time = Alarm.Schedule.Relative.Time(hour: minute / 60, minute: minute % 60)
            let schedule = Alarm.Schedule.relative(.init(time: time, repeats: .weekly(weekdays)))
            let id = UUID()
            do {
                _ = try await manager.schedule(id: id, configuration: .alarm(schedule: schedule,
                                                                             attributes: attributes))
                ids.append(id.uuidString)
            } catch {
                continue
            }
        }
        UserDefaults.standard.set(ids, forKey: idsKey)
        return !ids.isEmpty
    }

    static func cancelAll() {
        let ids = UserDefaults.standard.stringArray(forKey: idsKey) ?? []
        for id in ids.compactMap(UUID.init(uuidString:)) { try? AlarmManager.shared.cancel(id: id) }
        UserDefaults.standard.removeObject(forKey: idsKey)
    }

    /// Whether NOOP currently has a system wake alarm set.
    static var isScheduled: Bool { !(UserDefaults.standard.stringArray(forKey: idsKey) ?? []).isEmpty }

    private static func localeWeekday(_ calendarWeekday: Int) -> Locale.Weekday? {
        switch calendarWeekday {
        case 1: .sunday
        case 2: .monday
        case 3: .tuesday
        case 4: .wednesday
        case 5: .thursday
        case 6: .friday
        case 7: .saturday
        default: nil
        }
    }
}
#endif
