import SwiftUI

/// A picture of your day: when Tuloy pings, and when each fresh window starts.
///
/// The pale block is the early window Tuloy opens for you. The solid blocks
/// are the fresh ones you get to use.
struct DayTimeline: View {
    var schedule: Schedule
    var now: Date
    var calendar: Calendar = .current

    private let trackTop: CGFloat = 14
    private let trackHeight: CGFloat = 18
    private let labelWidth: CGFloat = 86

    var body: some View {
        if let fresh = schedule.nextFresh(after: now, calendar: calendar) {
            let windows = schedule.windows(endingFirstAt: fresh, calendar: calendar)
            VStack(alignment: .leading, spacing: 6) {
                Text(Format.day(fresh))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                GeometryReader { proxy in
                    chart(windows, fresh: fresh, width: proxy.size.width)
                }
                .frame(height: 52)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Format.day(fresh)): ping at \(time(windows[0].start)), fresh window at \(time(fresh))")
        }
    }

    private func chart(_ windows: [DateInterval], fresh: Date, width: CGFloat) -> some View {
        let dayStart = calendar.startOfDay(for: fresh)
        let x = { (date: Date) -> CGFloat in
            width * min(1, max(0, date.timeIntervalSince(dayStart) / (24 * 60 * 60)))
        }

        return ZStack(alignment: .topLeading) {
            // The hours, for reference.
            ForEach([0, 6, 12, 18], id: \.self) { hour in
                Text(dayStart.addingTimeInterval(TimeInterval(hour) * 3600).formatted(.dateTime.hour()))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .offset(x: width * CGFloat(hour) / 24)
            }

            RoundedRectangle(cornerRadius: 5)
                .fill(.quaternary)
                .frame(width: width, height: trackHeight)
                .offset(y: trackTop)

            ForEach(Array(windows.enumerated()), id: \.offset) { index, window in
                let start = x(window.start), end = x(window.end)
                if end - start > 3 {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(index == 0 ? 0.3 : 0.9))
                        .frame(width: end - start - 2, height: trackHeight)
                        .offset(x: start + 1, y: trackTop)
                }
            }

            if windows.count == 1 {
                // Without keep going, your fresh window starts with your first message
                // after it opens. The dashed block shows the earliest it can run.
                let start = x(fresh), end = x(fresh.addingTimeInterval(Schedule.window))
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    .frame(width: max(0, end - start - 2), height: trackHeight)
                    .offset(x: start + 1, y: trackTop)
            }

            if calendar.isDate(now, inSameDayAs: fresh) {
                Capsule()
                    .fill(.primary)
                    .frame(width: 2, height: trackHeight + 6)
                    .offset(x: x(now) - 1, y: trackTop - 3)
            }

            // A ping the night before is off the chart. The text under the chart covers it.
            if windows[0].start >= dayStart {
                mark("Ping \(time(windows[0].start))", at: x(windows[0].start), width: width)
            }
            mark("Fresh \(time(fresh))", at: x(fresh), width: width, emphasized: true)
            // Keep going: each later window starts fresh too.
            ForEach(windows.dropFirst(2), id: \.start) { window in
                mark(time(window.start), at: x(window.start), width: width)
            }
        }
    }

    /// A small tick under the track with a label, nudged to stay inside the chart.
    private func mark(_ text: String, at x: CGFloat, width: CGFloat, emphasized: Bool = false) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(.secondary)
                .frame(width: 1, height: 4)
                .offset(x: x - 0.5, y: trackTop + trackHeight + 1)
            Text(text)
                .font(.system(size: 10, weight: emphasized ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(emphasized ? .primary : .secondary)
                .lineLimit(1)
                .frame(width: labelWidth)
                .offset(x: min(max(0, x - labelWidth / 2), max(0, width - labelWidth)), y: trackTop + trackHeight + 6)
        }
    }

    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
