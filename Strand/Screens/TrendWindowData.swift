import StrandDesign
import SwiftUI
import WhoopStore

/// Resolving a metric's trend points from banked days for the Trends tab: the smallest window at or wider
/// than the selected range that holds data (the widening fallback a wearer with two weeks of history
/// depends on), and the padded y-range its chart plots on.
enum TrendWindowData {

    /// Day strings are banked as `yyyy-MM-dd` in UTC; parsing them any other way shifts every point.
    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// The metric's points for the smallest window at or wider than `selected` that holds any data,
    /// and the window it settled on.
    ///
    /// Walks the widening order ONCE, keeping the window's points rather than re-filtering to read them
    /// back. Falls back to all history when no window held anything, rather than leaving a new wearer with
    /// an empty chart.
    static func resolve(days: [DailyMetric],
                        selected: TrendsView.Range,
                        value: (DailyMetric) -> Double?) -> (points: [TrendPoint], effective: TrendsView.Range) {
        for r in selected.widening {
            let pts = points(window(days, r), value)
            if !pts.isEmpty { return (pts, r) }
        }
        return (points(window(days, .all), value), .all)
    }

    /// The trailing window of `days`, anchored on today's local day.
    private static func window(_ days: [DailyMetric], _ r: TrendsView.Range) -> [DailyMetric] {
        guard let n = r.days, n > 0 else { return days }
        let cutoff = Repository.localDayKey(
            Calendar.current.date(byAdding: .day, value: -(n - 1), to: Date()) ?? Date())
        return days.filter { $0.day >= cutoff }
    }

    /// The plotted y-range: the data's own span with a little air, the fixed fallback when there is no
    /// data at all, and a unit either side of a single repeated value so one flat line does not map onto
    /// a zero-width range.
    ///
    static func valueRange(_ pts: [TrendPoint], fallback: ClosedRange<Double>,
                           pad: Double = 0.12) -> ClosedRange<Double> {
        let vals = pts.map(\.value)
        guard let lo = vals.min(), let hi = vals.max() else { return fallback }
        if hi <= lo { return (lo - 1)...(hi + 1) }
        let span = hi - lo
        return (lo - span * pad)...(hi + span * pad)
    }

    private static func points(_ days: [DailyMetric], _ value: (DailyMetric) -> Double?) -> [TrendPoint] {
        days.compactMap { d in
            guard let v = value(d), let dt = dayParser.date(from: d.day) else { return nil }
            return TrendPoint(date: dt, value: v)
        }
    }
}
