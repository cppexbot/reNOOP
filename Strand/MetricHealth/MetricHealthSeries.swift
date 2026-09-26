//  MetricHealthSeries.swift
//  NOOP · Metric page — the pure half of the one page every metric opens on (the Health app's
//  per-type page on iOS 26: W / M / 6M / Y, an average over the period, one chart).
//
//  A metric's daily series in, the picked period out: its bounds, its buckets (days for W and M, weeks
//  for 6M, months for Y), the average the header prints, and the Highlights card's "latest against
//  your two-week average". No view state, so every figure on the page comes from here.

import Foundation

/// The period picker's four spans. There is no day view: every catalog series holds one value per day.
enum MetricHealthRange: String, CaseIterable, Identifiable {
    case week, month, sixMonths, year
    var id: String { rawValue }

    var label: String {
        switch self {
        case .week: return String(localized: "sleep.range.week", defaultValue: "W")
        case .month: return String(localized: "sleep.range.month", defaultValue: "M")
        case .sixMonths: return String(localized: "sleep.range.sixMonths", defaultValue: "6M")
        case .year: return String(localized: "metric.range.year", defaultValue: "Y")
        }
    }

    /// What one chart mark stands for.
    var bucket: Calendar.Component {
        switch self {
        case .week, .month: return .day
        case .sixMonths: return .weekOfYear
        case .year: return .month
        }
    }
}

/// One chart mark: a day's value, or the mean of the days on record in a week or a month.
struct MetricHealthPoint: Identifiable, Equatable {
    let start: Date
    /// Exclusive.
    let end: Date
    let value: Double
    /// How many days on record went into `value`.
    let count: Int
    /// The newest day in the bucket ("yyyy-MM-dd").
    let lastDay: String
    var id: Date { start }
}

struct MetricHealthWindow: Equatable {
    let range: MetricHealthRange
    let start: Date
    /// Exclusive.
    let end: Date
    /// The day the window ends on: today, or the newest reading when today's span is empty. 6M and Y run
    /// on to the end of that week or month; the span label stops here.
    let anchor: Date
    let points: [MetricHealthPoint]
    /// The day readings inside the window, oldest first — what the average and the correlations read.
    let days: [(day: String, value: Double)]

    /// The mean of the days on record, not of the buckets, so a short week does not weigh as much as a full one.
    var average: Double? {
        days.isEmpty ? nil : days.map(\.value).reduce(0, +) / Double(days.count)
    }

    static func == (lhs: MetricHealthWindow, rhs: MetricHealthWindow) -> Bool {
        lhs.range == rhs.range && lhs.start == rhs.start && lhs.end == rhs.end && lhs.points == rhs.points
    }
}

/// The Highlights card, as Health draws one on a data type's page: the newest reading against the mean
/// of the fortnight before it, with that fortnight's readings for its bars.
struct MetricHealthHighlight: Equatable {
    enum Direction: Equatable { case above, below, close }
    let latest: Double
    let average: Double
    /// The readings of the fortnight ending on the newest one, oldest first; the last is `latest`.
    let values: [Double]
    let firstDay: String
    let lastDay: String
    let direction: Direction
}

enum MetricHealthSeries {

    /// "yyyy-MM-dd" → local midnight.
    static func date(_ key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// The span a range covers when it ends on `anchor`'s day. Week and month end with that day; 6M runs
    /// whole weeks and Y whole months, so the first and last buckets are never cut in half.
    static func bounds(_ range: MetricHealthRange, anchor: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let day = calendar.startOfDay(for: anchor)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        switch range {
        case .week:
            return (calendar.date(byAdding: .day, value: -6, to: day) ?? day, dayEnd)
        case .month:
            return (calendar.date(byAdding: .month, value: -1, to: day) ?? day, dayEnd)
        case .sixMonths:
            let from = calendar.date(byAdding: .month, value: -6, to: dayEnd) ?? day
            let start = calendar.dateInterval(of: .weekOfYear, for: from)?.start ?? from
            let end = calendar.dateInterval(of: .weekOfYear, for: day)?.end ?? dayEnd
            return (start, end)
        case .year:
            let month = calendar.dateInterval(of: .month, for: day)
            let end = month?.end ?? dayEnd
            return (calendar.date(byAdding: .month, value: -12, to: end) ?? day, end)
        }
    }

    /// The picked range, ending today — or, when today's span has nothing on record, ending on the newest
    /// reading, so a series that stopped (a weekly weigh-in, an old import) still draws instead of "No Data".
    static func window(series: [(day: String, value: Double)], range: MetricHealthRange,
                       today: Date, calendar: Calendar) -> MetricHealthWindow {
        let dated = series.compactMap { row in date(row.day, calendar: calendar).map { (date: $0, row: row) } }
        var anchor = calendar.startOfDay(for: today)
        var span = bounds(range, anchor: anchor, calendar: calendar)
        let hasToday = dated.contains { $0.date >= span.start && $0.date < span.end }
        if !hasToday, let newest = dated.map(\.date).max(), newest < span.start {
            anchor = newest
            span = bounds(range, anchor: newest, calendar: calendar)
        }
        let inside = dated.filter { $0.date >= span.start && $0.date < span.end }.sorted { $0.date < $1.date }

        var points: [MetricHealthPoint] = []
        var bucketStart: Date?
        var bucketEnd = span.start
        var values: [Double] = []
        var lastDay = ""
        func flush() {
            guard let s = bucketStart, !values.isEmpty else { return }
            points.append(MetricHealthPoint(start: s, end: bucketEnd, value: values.reduce(0, +) / Double(values.count),
                                            count: values.count, lastDay: lastDay))
        }
        for item in inside {
            let interval = calendar.dateInterval(of: range.bucket, for: item.date)
                ?? DateInterval(start: item.date, duration: 86_400)
            if interval.start != bucketStart {
                flush()
                bucketStart = interval.start
                bucketEnd = interval.end
                values = []
            }
            values.append(item.row.value)
            lastDay = item.row.day
        }
        flush()
        return MetricHealthWindow(range: range, start: span.start, end: span.end, anchor: anchor, points: points,
                                  days: inside.map(\.row))
    }

    /// The newest reading against the mean of the readings in the 13 days before it. Needs four of them,
    /// so a single earlier night is never called "your average". Within 5 % of it reads as "close".
    static func highlight(series: [(day: String, value: Double)], calendar: Calendar) -> MetricHealthHighlight? {
        guard let last = series.last, let lastDate = date(last.day, calendar: calendar),
              let from = calendar.date(byAdding: .day, value: -13, to: lastDate) else { return nil }
        let recent = series.filter { row in date(row.day, calendar: calendar).map { $0 >= from && $0 <= lastDate } ?? false }
        let prior = recent.dropLast().map(\.value)
        guard prior.count >= 4, let first = recent.first else { return nil }
        let average = prior.reduce(0, +) / Double(prior.count)
        let direction: MetricHealthHighlight.Direction =
            abs(last.value - average) <= 0.05 * max(abs(average), 1e-9) ? .close : (last.value > average ? .above : .below)
        return MetricHealthHighlight(latest: last.value, average: average, values: recent.map(\.value),
                                     firstDay: first.day, lastDay: last.day, direction: direction)
    }

    // MARK: - Labels

    /// "20–26 Sep 2026" / "Nov 2025 – Oct 2026": the span under the header figure.
    static func spanLabel(_ window: MetricHealthWindow, calendar: Calendar, locale: Locale) -> String {
        let last = min(calendar.date(byAdding: .day, value: -1, to: window.end) ?? window.end, window.anchor)
        return interval(window.start, last, template: window.range == .year ? "MMMy" : "dMMMy",
                        calendar: calendar, locale: locale)
    }

    /// The date a picked mark stands for: its day, its week, or its month.
    static func pointLabel(_ point: MetricHealthPoint, range: MetricHealthRange,
                           calendar: Calendar, locale: Locale) -> String {
        switch range.bucket {
        case .day:
            let f = DateFormatter()
            f.calendar = calendar
            f.locale = locale
            f.setLocalizedDateFormatFromTemplate("EEEdMMMy")
            return f.string(from: point.start)
        case .weekOfYear:
            let last = calendar.date(byAdding: .day, value: -1, to: point.end) ?? point.end
            return interval(point.start, last, template: "dMMMy", calendar: calendar, locale: locale)
        default:
            let f = DateFormatter()
            f.calendar = calendar
            f.locale = locale
            f.setLocalizedDateFormatFromTemplate("LLLLy")
            return f.string(from: point.start)
        }
    }

    private static func interval(_ from: Date, _ to: Date, template: String,
                                 calendar: Calendar, locale: Locale) -> String {
        let f = DateIntervalFormatter()
        f.calendar = calendar
        f.locale = locale
        f.dateTemplate = template
        return f.string(from: from, to: to)
    }
}
