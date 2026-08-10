import SwiftUI

/// Week view: lists each day's time record and completion counts; clicking a day returns to day view.
struct WeekView: View {
    @ObservedObject var service: TodoService

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
                Spacer()
                Label(service.weekTotalText, systemImage: "clock")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            ForEach(visibleDays) { day in
                Button {
                    service.goToDay(day.date)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(DayName.heading(day.date))
                                .font(.body.weight(.semibold))
                            Text(I18n.t("待办 \(day.followup.count) · 未完成 \(day.uncompleted.count)",
                                        "Todo \(day.followup.count) · Unfinished \(day.uncompleted.count)"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if day.time.clockIn != nil {
                                HStack(spacing: 10) {
                                    Text(I18n.t("上班 \(day.time.clockIn ?? "--:--")", "In \(day.time.clockIn ?? "--:--")"))
                                    Text(I18n.t("下班 \(day.time.clockOut ?? "--:--")", "Out \(day.time.clockOut ?? "--:--")"))
                                    if let loc = day.time.location, !loc.isEmpty {
                                        Text(loc)
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(I18n.t("完成 \(day.completed.count)", "Done \(day.completed.count)"))
                                .font(.caption)
                                .foregroundStyle(Palette.completed)
                            if let dur = day.time.duration {
                                Text(dur)
                                    .font(.caption.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            } else if day.time.clockIn != nil {
                                Text(I18n.t("未下班", "Working"))
                                    .font(.caption2)
                                    .foregroundStyle(Palette.followup)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 8)
                .padding(.horizontal, 4)

                if day.id != visibleDays.last?.id {
                    Divider()
                }
            }
        }
    }
}
