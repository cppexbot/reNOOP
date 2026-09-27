//  HealthTrendDetector.swift
//  NOOP · Trends — whether a metric's recent readings have moved away from where they were, read the way
//  Health's Trends read it: one span split into an earlier and a recent period ("Trending lower for 12
//  weeks", "18-week avg" against "12-week avg"), the split placed where the two periods differ most.
//
//  Pure: a daily series in, one result out. Two scales are tried, weeks first (a long trend is the bigger
//  story), then days.

import Foundation

struct HealthTrend: Equatable {
    enum Direction: Equatable { case higher, lower }
    /// What one slot of the span stands for.
    enum Unit: Equatable { case day, week }

    let direction: Direction
    let unit: Unit
    /// Every slot of the span, oldest first: a day's reading or a week's mean, nil where nothing was recorded.
    let slots: [Double?]
    /// How many trailing slots form the recent period ("for 5 days"); the slots before it are the baseline.
    let recentCount: Int
    let baselineAverage: Double
    let recentAverage: Double
    /// Welch's t between the two periods: how clearly they differ. Orders trends by strength.
    let strength: Double
    /// Whether the move is good news; nil for a metric with no better direction.
    let isImprovement: Bool?

    var baselineCount: Int { slots.count - recentCount }
    /// The baseline's length from its first reading: what its average actually covers ("14-week avg"),
    /// not counting the empty start of a span a short history does not reach.
    var baselineLength: Int { baselineCount - (slots.firstIndex { $0 != nil } ?? 0) }
}

enum HealthTrendResult: Equatable {
    case trend(HealthTrend)
    /// Enough recent readings to judge, and no clear change.
    case steady
    /// Too few readings, or none recent enough, to say anything.
    case insufficient
}

enum HealthTrendDetector {

    /// One way of reading the span: its slot, how many slots it covers, where the recent period may start,
    /// and how many readings each period needs before a comparison means anything.
    struct Scale: Equatable {
        let unit: HealthTrend.Unit
        let span: Int
        let recentLengths: ClosedRange<Int>
        let minRecentPoints: Int
        let minBaselinePoints: Int
        /// The newest slots of which at least one must hold a reading: a trend is about now.
        let freshSlots: Int
    }

    static let weekly = Scale(unit: .week, span: 26, recentLengths: 4...13,
                              minRecentPoints: 3, minBaselinePoints: 6, freshSlots: 1)
    static let daily = Scale(unit: .day, span: 28, recentLengths: 5...14,
                             minRecentPoints: 4, minBaselinePoints: 10, freshSlots: 3)

    /// The |t| a split must reach. Every candidate split is a test of its own, so the bar sits well above the
    /// 1.96 a single comparison would use.
    static let minStrength = 3.0
    /// The smallest change worth a card, in standard deviations of the baseline: a consistent drift smaller
    /// than the everyday wobble is not news.
    static let minEffect = 0.5
    /// The share of recent readings that must sit on the trend's side of the baseline average, so a couple
    /// of outliers cannot carry a period.
    static let minAgreement = 0.7

    /// The metric's trend as of `today` ("yyyy-MM-dd"). The series is one value per "yyyy-MM-dd" day.
    static func detect(series: [(day: String, value: Double)], today: String,
                       higherIsBetter: Bool?) -> HealthTrendResult {
        guard let todayIndex = dayNumber(today) else { return .insufficient }
        var byDay: [Int: Double] = [:]
        for row in series {
            if let n = dayNumber(row.day) { byDay[n] = row.value }
        }
        var judged = false
        for scale in [weekly, daily] {
            switch best(slots(byDay, today: todayIndex, scale: scale), scale: scale, higherIsBetter: higherIsBetter) {
            case .trend(let trend): return .trend(trend)
            case .steady: judged = true
            case .insufficient: break
            }
        }
        return judged ? .steady : .insufficient
    }

    /// Worse news first (a warning must not sit under a compliment), then good news, then moves with no
    /// better direction; the clearer trend first within each.
    static func precedes(_ a: HealthTrend, _ b: HealthTrend) -> Bool {
        func rank(_ t: HealthTrend) -> Int {
            switch t.isImprovement {
            case false?: return 0
            case true?: return 1
            case nil: return 2
            }
        }
        return rank(a) != rank(b) ? rank(a) < rank(b) : abs(a.strength) > abs(b.strength)
    }

    // MARK: - Internals

    /// The span's slots, oldest first, ending with the slot that holds `today`. A week slot is the mean of
    /// the readings in its seven days.
    static func slots(_ byDay: [Int: Double], today: Int, scale: Scale) -> [Double?] {
        let width = scale.unit == .week ? 7 : 1
        return (0..<scale.span).map { k in
            let last = today - width * (scale.span - 1 - k)
            let values = (last - width + 1...last).compactMap { byDay[$0] }
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
    }

    private static func best(_ slots: [Double?], scale: Scale, higherIsBetter: Bool?) -> HealthTrendResult {
        let recorded = slots.compactMap { $0 }
        guard recorded.count >= scale.minRecentPoints + scale.minBaselinePoints,
              slots.suffix(scale.freshSlots).contains(where: { $0 != nil }) else { return .insufficient }
        var found: HealthTrend?
        var judged = false
        for length in scale.recentLengths {
            let recent = slots.suffix(length).compactMap { $0 }
            let baseline = slots.prefix(slots.count - length).compactMap { $0 }
            guard recent.count >= scale.minRecentPoints, baseline.count >= scale.minBaselinePoints else { continue }
            judged = true
            let mr = mean(recent), mb = mean(baseline)
            let vr = variance(recent, mr), vb = variance(baseline, mb)
            let se = (vr / Double(recent.count) + vb / Double(baseline.count)).squareRoot()
            let delta = mr - mb
            guard delta != 0 else { continue }
            let t = delta / max(se, 1e-9)
            let effect = abs(delta) / max(vb.squareRoot(), 1e-9)
            let agreeing = recent.filter { delta > 0 ? $0 > mb : $0 < mb }.count
            guard abs(t) >= minStrength, effect >= minEffect,
                  Double(agreeing) / Double(recent.count) >= minAgreement else { continue }
            // Ties go to the longer recent period: the same evidence reads as the longer-lived trend.
            if let current = found, abs(t) < abs(current.strength) { continue }
            let direction: HealthTrend.Direction = delta > 0 ? .higher : .lower
            found = HealthTrend(direction: direction, unit: scale.unit, slots: slots, recentCount: length,
                                baselineAverage: mb, recentAverage: mr, strength: t,
                                isImprovement: higherIsBetter.map { $0 == (direction == .higher) })
        }
        if let found { return .trend(found) }
        return judged ? .steady : .insufficient
    }

    private static func mean(_ v: [Double]) -> Double { v.reduce(0, +) / Double(v.count) }

    private static func variance(_ v: [Double], _ m: Double) -> Double {
        guard v.count > 1 else { return 0 }
        return v.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(v.count - 1)
    }

    /// "yyyy-MM-dd" → days since 1970-01-01 in the proleptic Gregorian calendar (no time zone, no DST).
    static func dayNumber(_ key: String) -> Int? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        let y = parts[1] <= 2 ? parts[0] - 1 : parts[0]
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let m = parts[1], d = parts[2]
        let doy = (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }
}
