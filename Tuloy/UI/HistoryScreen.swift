import SwiftUI

/// History: a square for every day, like a contribution chart, and every ping of the last month.
struct HistoryContent: View {
    let model: AppModel
    /// The day picked in the chart, to show only its pings.
    @State private var picked: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("History")
                    .font(.title2.weight(.semibold))
                Text("Every ping Tuloy sent, and what came back. The squares count the pings that got through each day; the list keeps the last month in full.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    PingChart(days: model.pingDays, today: model.now, calendar: model.calendar, picked: $picked)
                    Totals(days: model.pingDays, history: model.history, today: model.now, calendar: model.calendar)
                }
            }

            pingList
        }
    }

    // MARK: - The list

    private var shown: [PingRecord] {
        guard let picked else { return model.history }
        return model.history.filter { PingDay.key(for: $0.date, calendar: model.calendar) == picked }
    }

    @ViewBuilder
    private var pingList: some View {
        HStack {
            Text(picked.map { "Pings on \(PingChart.longName(of: $0, calendar: model.calendar))" } ?? "Every ping, last 31 days")
                .font(.headline)
            Spacer()
            if picked != nil {
                Button("Show All") { picked = nil }
                    .buttonStyle(TuloyButtonStyle())
            }
        }

        if shown.isEmpty {
            Text(picked == nil ? "No pings yet. Each one Tuloy sends shows up here." : "No pings that day, or it's more than a month ago: only the count is kept that long.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        let days = Dictionary(grouping: shown) { model.calendar.startOfDay(for: $0.date) }
        ForEach(days.keys.sorted(by: >), id: \.self) { day in
            VStack(alignment: .leading, spacing: 6) {
                Text(Format.dayTitle(day, now: model.now, calendar: model.calendar))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(days[day] ?? [], id: \.date) { ping in
                    PingRow(ping: ping)
                }
            }
            .padding(.top, 4)
        }
    }
}

/// One ping, on one line: what happened, when, why it was sent, and what it cost.
struct PingRow: View {
    var ping: PingRecord

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: ping.hitTheLimit ? "minus.circle.fill" : ping.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ping.hitTheLimit ? AnyShapeStyle(.secondary) : ping.ok ? AnyShapeStyle(.green) : AnyShapeStyle(.orange))
            Text(ping.timeText)
                .monospacedDigit()
                .frame(width: 118, alignment: .leading)
            Text(ping.kindText)
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(ping.outcomeText + (ping.timesText.map { " \($0)" } ?? ""))
                    .lineLimit(2)
                if let late = ping.lateText {
                    Text(late)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if let tokens = ping.tokens {
                Text("\(tokens) tokens")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }
}

/// A square for each day, a column for each week, darker for more pings. Click one for its pings.
struct PingChart: View {
    var days: [String: PingDay]
    var today: Date
    var calendar: Calendar
    @Binding var picked: String?

    private let cell: CGFloat = 12
    private let gap: CGFloat = 3
    private let labels: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let weeks = max(4, min(53, Int((proxy.size.width - labels) / (cell + gap))))
                grid(weeks: weeks)
            }
            .frame(height: 16 + 7 * (cell + gap))

            HStack(spacing: 4) {
                Text("Fewer")
                ForEach(0..<5) { level in
                    RoundedRectangle(cornerRadius: 2.5).fill(PingChart.color(level: level)).frame(width: 10, height: 10)
                }
                Text("More")
                Spacer()
                RoundedRectangle(cornerRadius: 2.5).fill(.orange.opacity(0.55)).frame(width: 10, height: 10)
                Text("Only failed")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func grid(weeks: Int) -> some View {
        let columns = PingChart.columns(weeks: weeks, ending: today, calendar: calendar)
        let todayKey = PingDay.key(for: today, calendar: calendar)

        return HStack(alignment: .top, spacing: gap) {
            // Weekday names down the side: every other row, as GitHub does.
            VStack(alignment: .leading, spacing: gap) {
                Color.clear.frame(height: 13)
                ForEach(0..<7, id: \.self) { row in
                    Text(row % 2 == 1 ? weekdayName(row: row) : "")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .frame(width: labels - gap, height: cell, alignment: .leading)
                }
            }
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                VStack(spacing: gap) {
                    Text(monthLabel(for: column, index: index, columns: columns))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                        .frame(width: cell, height: 13, alignment: .leading)
                    ForEach(0..<7, id: \.self) { row in
                        square(for: column[row], isToday: column[row].map { PingDay.key(for: $0, calendar: calendar) } == todayKey)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func square(for date: Date?, isToday: Bool) -> some View {
        if let date {
            let key = PingDay.key(for: date, calendar: calendar)
            let day = days[key]
            Button {
                picked = picked == key ? nil : key
            } label: {
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(fill(for: day))
                    .frame(width: cell, height: cell)
                    .overlay {
                        if picked == key || isToday {
                            RoundedRectangle(cornerRadius: 2.5).strokeBorder(picked == key ? Color.primary : Color.secondary, lineWidth: 1.2)
                        }
                    }
            }
            .buttonStyle(.plain)
            .help(PingChart.summary(of: day, on: key, calendar: calendar))
            .accessibilityLabel(PingChart.summary(of: day, on: key, calendar: calendar))
        } else {
            Color.clear.frame(width: cell, height: cell)
        }
    }

    private func fill(for day: PingDay?) -> Color {
        guard let day else { return PingChart.color(level: 0) }
        if day.sent == 0, day.failed > 0 { return .orange.opacity(0.55) }
        return PingChart.color(level: min(4, day.sent))
    }

    static func color(level: Int) -> Color {
        level == 0 ? Color.primary.opacity(0.08) : Color.accentColor.opacity([0, 0.35, 0.55, 0.78, 1][level])
    }

    /// The days to draw, a column per week, oldest first, ending with this week. Days still to come are nil.
    static func columns(weeks: Int, ending today: Date, calendar: Calendar) -> [[Date?]] {
        let start = calendar.startOfDay(for: today)
        let weekday = calendar.component(.weekday, from: start)
        let back = (weekday - calendar.firstWeekday + 7) % 7
        guard let thisWeek = calendar.date(byAdding: .day, value: -back, to: start),
              let first = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek)
        else { return [] }

        return (0..<weeks).map { week in
            (0..<7).map { row in
                guard let date = calendar.date(byAdding: .day, value: week * 7 + row, to: first), date <= start else { return nil }
                return date
            }
        }
    }

    /// "Mon, 19 Oct: 2 pings got through (1 by you), 1 didn't."
    static func summary(of day: PingDay?, on key: String, calendar: Calendar) -> String {
        let name = longName(of: key, calendar: calendar)
        guard let day, day.sent + day.failed > 0 else { return "\(name): no pings" }
        var parts = ["\(day.sent) \(day.sent == 1 ? "ping" : "pings") got through"]
        if day.byYou > 0 { parts[0] += " (\(day.byYou) by you)" }
        if day.failed > 0 { parts.append("\(day.failed) didn't") }
        return "\(name): " + parts.joined(separator: ", ")
    }

    /// "Mon, 19 Oct", from a day's key.
    static func longName(of key: String, calendar: Calendar) -> String {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return key }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private func weekdayName(row: Int) -> String {
        let day = (calendar.firstWeekday - 1 + row) % 7
        return String(calendar.shortWeekdaySymbols[day].prefix(3))
    }

    /// The month's name over the first column that starts a new month.
    private func monthLabel(for column: [Date?], index: Int, columns: [[Date?]]) -> String {
        guard let first = column.compactMap({ $0 }).first else { return "" }
        let month = calendar.component(.month, from: first)
        if index > 0, let previous = columns[index - 1].compactMap({ $0 }).first,
           calendar.component(.month, from: previous) == month {
            return ""
        }
        // Skip a label squeezed in on the very first column if the next one starts a month too.
        return index == 0 && calendar.component(.day, from: first) > 21 ? "" : first.formatted(.dateTime.month(.abbreviated))
    }
}

/// A few numbers under the chart.
private struct Totals: View {
    var days: [String: PingDay]
    var history: [PingRecord]
    var today: Date
    var calendar: Calendar

    var body: some View {
        let monthTokens = history.compactMap(\.tokens).reduce(0, +)
        let sentThisMonth = history.filter(\.ok).count
        HStack(spacing: 18) {
            figure("\(days.values.reduce(0) { $0 + $1.sent })", "pings got through")
            figure("\(days.values.filter { $0.sent > 0 }.count)", "days with a ping")
            figure("\(streak)", streak == 1 ? "day in a row" : "days in a row")
            figure(monthTokens.formatted(), "tokens in 31 days")
        }
        .help("In the last 31 days, \(sentThisMonth) pings got through and used \(monthTokens.formatted()) tokens of your plan's allowance between them. Usage checks are free and aren't counted.")
    }

    /// Days in a row, up to today, with at least one ping through. Today counts once it has one.
    private var streak: Int {
        var count = 0
        var day = calendar.startOfDay(for: today)
        if (days[PingDay.key(for: day, calendar: calendar)]?.sent ?? 0) == 0 {
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        while (days[PingDay.key(for: day, calendar: calendar)]?.sent ?? 0) > 0, count < 400 {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    private func figure(_ number: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(number)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
