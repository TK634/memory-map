import SwiftUI

/// 旅行の実績カレンダー。行った日を塗って「いつ・どこへ行ったか」を一目で見せる。
struct TravelCalendarView: View {
    let places: [Place]
    let members: [Member]
    /// 上に重なるヘッダー分の余白
    var topInset: CGFloat = 6
    /// 日付を選んで登録を始める
    var onAddOnDate: (Date) -> Void = { _ in }
    var onSelectPlace: (Place) -> Void

    @State private var selectedDay: DaySelection?
    @State private var showUndated = false
    /// 日の詳細シートを閉じたあとに登録を始める日
    @State private var addAfterDismiss: Date?

    struct DaySelection: Identifiable {
        let date: Date
        var id: TimeInterval { date.timeIntervalSince1970 }
    }

    private var cal: Calendar { Calendar.current }

    // MARK: - 集計

    /// 日付 → その日の記録(泊まりの旅は期間中すべての日に入る)
    private func buildDayMap() -> [Date: [Place]] {
        var map: [Date: [Place]] = [:]
        for p in places {
            guard let start = p.visitDate else { continue }
            let s = cal.startOfDay(for: start)
            let e = cal.startOfDay(for: p.visitEndDate ?? start)
            var d = s
            var steps = 0
            while d <= e && steps < 400 {
                map[d, default: []].append(p)
                guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
                d = next
                steps += 1
            }
        }
        return map
    }

    /// 日付が未設定の記録
    private var undatedPlaces: [Place] {
        places.filter { $0.visitDate == nil }
    }

    /// 表示する月(新しい順)。今月と、記録がある月だけ(空の月でスクロールが長くならないように)
    private func months(from map: [Date: [Place]]) -> [Date] {
        var set = Set(map.keys.map(monthStart))
        set.insert(monthStart(Date()))
        return set.sorted(by: >)
    }

    private func monthStart(_ date: Date) -> Date {
        cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
    }

    /// 今年の記録数
    private var thisYearCount: Int {
        let y = cal.component(.year, from: Date())
        return places.filter { Int($0.year) == y }.count
    }

    // MARK: - UI

    var body: some View {
        let map = buildDayMap()
        ScrollView {
            LazyVStack(spacing: 18, pinnedViews: []) {
                summaryCard
                ForEach(months(from: map), id: \.self) { month in
                    monthSection(month, map: map)
                }
                if !undatedPlaces.isEmpty {
                    undatedCard
                }
                Color.clear.frame(height: 96)   // 下部バーの余白
            }
            .padding(.horizontal, 14)
            .padding(.top, topInset)
        }
        .background(Color(hex: "FFF8EF"))
        .sheet(item: $selectedDay, onDismiss: {
            if let d = addAfterDismiss {
                addAfterDismiss = nil
                onAddOnDate(d)
            }
        }) { sel in
            DayDetailSheet(date: sel.date,
                           places: (buildDayMap()[sel.date] ?? []),
                           members: members,
                           onAdd: {
                               addAfterDismiss = sel.date
                               selectedDay = nil
                           }) { p in
                selectedDay = nil
                onSelectPlace(p)
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showUndated) {
            DayDetailSheet(date: nil, places: undatedPlaces, members: members) { p in
                showUndated = false
                onSelectPlace(p)
            }
            .presentationDetents([.medium])
        }
    }

    /// 今年のサマリー
    private var summaryCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "shoeprints.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(AppPalette.accent, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("今年のあしあと")
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(thisYearCount)か所")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppPalette.chrome)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Image(systemName: "hand.tap.fill")
                    .foregroundStyle(AppPalette.accent)
                Text("日付をタップして\n行った場所を登録")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
    }

    /// 日付未設定の記録
    private var undatedCard: some View {
        Button { showUndated = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .foregroundStyle(.secondary)
                Text("日付が未設定の記録 \(undatedPlaces.count)件")
                    .font(.footnote.bold()).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 月

    private func monthSection(_ month: Date, map: [Date: [Place]]) -> some View {
        let days = daySlots(of: month)
        let monthCount = countInMonth(month, map: map)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(monthTitle(month))
                    .font(.subheadline.bold())
                    .foregroundStyle(AppPalette.chrome)
                Spacer()
                if monthCount > 0 {
                    Text("\(monthCount)か所")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(AppPalette.accent, in: Capsule())
                }
            }
            weekdayHeader
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7),
                      spacing: 4) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day, records: map[day] ?? [])
                    } else {
                        Color.clear.frame(height: 38)
                    }
                }
            }
        }
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
    }

    private var weekdayHeader: some View {
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let ordered = Array(symbols[(cal.firstWeekday - 1)...] + symbols[..<(cal.firstWeekday - 1)])
        return HStack(spacing: 2) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, s in
                Text(s)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// 月の日セル(先頭の空白を nil で埋める)
    private func daySlots(of month: Date) -> [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        let firstWeekday = cal.component(.weekday, from: month)
        let leading = (firstWeekday - cal.firstWeekday + 7) % 7
        var slots: [Date?] = Array(repeating: nil, count: leading)
        for d in range {
            if let date = cal.date(byAdding: .day, value: d - 1, to: month) {
                slots.append(cal.startOfDay(for: date))
            }
        }
        return slots
    }

    private func countInMonth(_ month: Date, map: [Date: [Place]]) -> Int {
        var ids = Set<NSManagedObjectID>()
        for (day, ps) in map where cal.isDate(day, equalTo: month, toGranularity: .month) {
            ps.forEach { ids.insert($0.objectID) }
        }
        return ids.count
    }

    private func monthTitle(_ month: Date) -> String {
        month.formatted(.dateTime.year().month(.wide).locale(AppRegion.preferredLocale))
    }

    /// 1日分のセル
    private func dayCell(_ date: Date, records: [Place]) -> some View {
        let hasRecord = !records.isEmpty
        let isToday = cal.isDateInToday(date)
        let fill: Color = {
            guard hasRecord else { return .clear }
            if records.count == 1 { return records[0].pinColor(members: members) }
            return AppPalette.accent
        }()
        return Button {
            if hasRecord {
                selectedDay = DaySelection(date: date)
            } else {
                onAddOnDate(date)
            }
        } label: {
            ZStack {
                if hasRecord {
                    Circle().fill(fill)
                } else if isToday {
                    Circle().fill(AppPalette.accent.opacity(0.12))
                }
                if isToday && hasRecord {
                    Circle().stroke(AppPalette.chrome, lineWidth: 2)
                }
                Text("\(cal.component(.day, from: date))")
                    .font(.system(size: 13, weight: hasRecord ? .heavy : .medium, design: .rounded))
                    .foregroundStyle(hasRecord ? .white : Color.primary.opacity(0.65))
            }
            .frame(height: 38)
        }
        .buttonStyle(.plain)
    }
}

import CoreData

/// 選んだ日の記録一覧
private struct DayDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let date: Date?
    let places: [Place]
    let members: [Member]
    /// この日に場所を追加(日付が未設定の一覧では nil)
    var onAdd: (() -> Void)? = nil
    var onSelect: (Place) -> Void

    var body: some View {
        NavigationStack {
            List {
                if let onAdd {
                    Button(action: onAdd) {
                        Label("この日に行った場所を追加", systemImage: "plus.circle.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(AppPalette.accent)
                    }
                }
                ForEach(places, id: \.objectID) { p in
                    Button { onSelect(p) } label: {
                        HStack(spacing: 12) {
                            PinView(color: p.pinColor(members: members))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name ?? "")
                                    .font(.subheadline.bold()).foregroundStyle(.primary)
                                Text(p.whoLabel(members: members))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle(date.map { $0.jaDateText } ?? String(localized: "日付が未設定の記録"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
        }
    }
}
