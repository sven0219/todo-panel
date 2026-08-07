import SwiftUI

/// Week view: lists each day's time record and completion counts; clicking a day returns to day view.
struct WeekView: View {
    @ObservedObject var service: TodoService

    /// Weekends without any records are hidden by default.
    private var visibleDays: [DayRecord] {
        service.weekDays.filter { day in
            if !DateMath.isWeekend(day.date) { return true }
            let empty = day.completed.isEmpty
                && day.followup.isEmpty
                && day.uncompleted.isEmpty
                && day.time.clockIn == nil
            return !empty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(I18n.t("本周概览", "This Week"))
                    .font(.headline)
                    .fontDesign(.rounded)
                Spacer()
                Label(service.weekTotalText, systemImage: "clock")
                    .font(.caption.bold())
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            ForEach(visibleDays) { day in
                Button {
                    service.goToDay(day.date)
                } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(DayName.heading(day.date))
                                .font(.callout.bold())
                                .fontDesign(.rounded)
                            Text(I18n.t("待办 \(day.followup.count) · 未完成 \(day.uncompleted.count)",
                                        "Todo \(day.followup.count) · Unfinished \(day.uncompleted.count)"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if day.time.clockIn != nil {
                                HStack(spacing: 8) {
                                    Text(I18n.t("上班 \(day.time.clockIn ?? "--:--")", "In \(day.time.clockIn ?? "--:--")"))
                                    Text(I18n.t("下班 \(day.time.clockOut ?? "--:--")", "Out \(day.time.clockOut ?? "--:--")"))
                                    if let loc = day.time.location, !loc.isEmpty {
                                        Text(I18n.t("地点 \(loc)", "Loc \(loc)"))
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(I18n.t("完成 \(day.completed.count)", "Done \(day.completed.count)"))
                                .font(.caption)
                                .foregroundStyle(Palette.completed)
                            if let dur = day.time.duration {
                                Text(dur)
                                    .font(.caption.bold())
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            } else if day.time.clockIn != nil {
                                Text(I18n.t("未下班", "Working"))
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.background.opacity(0.9))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(.primary.opacity(0.06), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
