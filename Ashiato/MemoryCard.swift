import SwiftUI
import CoreData

/// 「1年前の今日」の思い出を掘り起こす仕組み。
/// 旅行しない日でもアプリを開く理由をつくる(みてね式の再訪動線)。
enum MemoryLane {

    /// 今日と同じ月日の過去の記録(新しい順)
    static func todaysMemories(from places: [Place]) -> [Place] {
        let cal = Calendar.current
        let today = cal.dateComponents([.month, .day], from: Date())
        let thisYear = cal.component(.year, from: Date())
        return places.filter { p in
            guard let d = p.visitDate else { return false }
            let c = cal.dateComponents([.month, .day, .year], from: d)
            return c.month == today.month && c.day == today.day && c.year != thisYear
        }
        .sorted { ($0.visitDate ?? .distantPast) > ($1.visitDate ?? .distantPast) }
    }

    /// 何年前かの表示文
    static func yearsAgoText(for place: Place) -> String {
        guard let d = place.visitDate else { return "" }
        let years = Calendar.current.dateComponents([.year], from: d, to: Date()).year ?? 0
        return years <= 0 ? "今年の今日" : "\(years)年前の今日"
    }

    /// 毎朝9時に「今日の思い出」を知らせるローカル通知を予約
    @MainActor
    static func scheduleDailyReminder(places: [Place]) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["memoryLaneDaily"])

        let memories = todaysMemories(from: places)
        guard let first = memories.first else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(yearsAgoText(for: first))のあしあと"
        content.body = memories.count > 1
            ? "「\(first.name ?? "")」ほか\(memories.count - 1)件の思い出があります。"
            : "「\(first.name ?? "")」に行った日です。"
        content.sound = .default

        var comps = DateComponents()
        comps.hour = 9
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: "memoryLaneDaily",
                                         content: content, trigger: trigger))
    }
}

import UserNotifications

/// 地図の下部に出す「今日の思い出」カード
struct MemoryCardView: View {
    let memories: [Place]
    let onTap: (Place) -> Void
    @Binding var dismissedDate: String

    private var todayKey: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    var body: some View {
        if !memories.isEmpty, dismissedDate != todayKey, let first = memories.first {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(AppPalette.accent.opacity(0.15)).frame(width: 42, height: 42)
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppPalette.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(MemoryLane.yearsAgoText(for: first))
                        .font(.caption.bold())
                        .foregroundStyle(AppPalette.accent)
                    Text(memories.count > 1
                         ? "「\(first.name ?? "")」ほか\(memories.count - 1)件"
                         : "「\(first.name ?? "")」に行きました")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    withAnimation { dismissedDate = todayKey }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
            .onTapGesture { onTap(first) }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
