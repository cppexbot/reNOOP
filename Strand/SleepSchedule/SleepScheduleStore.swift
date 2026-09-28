//  SleepScheduleStore.swift
//  NOOP · Sleep schedule — reads the stored alarm / reminder settings into `SleepScheduleInputs` and
//  writes an edit back to the same keys, re-arming the strap once.

import Foundation

@MainActor
enum SleepScheduleStore {
    static func inputs(behavior: BehaviorStore, model: AppModel) -> SleepScheduleInputs {
        SleepScheduleInputs(alarmOn: behavior.smartAlarmEnabled,
                            // #864: a WHOOP 5/MG arms its firmware alarm only with Experimental on.
                            alarmWillArm: !(model.whoop5Detected && !PuffinExperiment.isEnabled),
                            baseWake: behavior.smartAlarmMinutes,
                            alarmDays: behavior.smartAlarmWeekdays,
                            overrides: WindDownNudge.perDayWakeOverrides,
                            sleepGoal: WindDownNudge.sleepNeedMinutes)
    }

    /// Writes `stored` over `old` — the base wake into both the alarm and the reminder (one wake time),
    /// only the per-day times that changed — then re-arms the strap alarm and its backup once.
    static func write(_ stored: SleepScheduleStored, over old: SleepScheduleInputs,
                      behavior: BehaviorStore, model: AppModel) {
        if behavior.smartAlarmMinutes != stored.baseWake { behavior.smartAlarmMinutes = stored.baseWake }
        if WindDownNudge.wakeMinutes != stored.baseWake { WindDownNudge.setWakeMinutes(stored.baseWake) }
        if behavior.smartAlarmWeekdays != stored.alarmDays { behavior.smartAlarmWeekdays = stored.alarmDays }
        for d in 1...7 where old.overrides[d] != stored.overrides[d] {
            WindDownNudge.setWakeOverride(weekday: d, minutes: stored.overrides[d])
        }
        if WindDownNudge.sleepNeedMinutes != stored.sleepGoal { WindDownNudge.setSleepNeedMinutes(stored.sleepGoal) }
        model.applySmartAlarm(userInitiated: true)
    }

    /// Gives the alarm and the reminder one base wake time when they were stored apart (see
    /// `SleepSchedule.reconciledBaseWake`). Runs once at launch; touches the strap only through the
    /// normal re-arm, and only when the alarm's own time changes (it never does while the alarm is on).
    static func reconcileBaseWake(behavior: BehaviorStore) {
        let wake = SleepSchedule.reconciledBaseWake(alarmOn: behavior.smartAlarmEnabled,
                                                    alarmWake: behavior.smartAlarmMinutes,
                                                    reminderOn: WindDownNudge.isEnabled,
                                                    reminderWake: WindDownNudge.wakeMinutes)
        if behavior.smartAlarmMinutes != wake { behavior.smartAlarmMinutes = wake }
        if WindDownNudge.wakeMinutes != wake { WindDownNudge.setWakeMinutes(wake) }
    }
}
