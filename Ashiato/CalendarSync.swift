import SwiftUI
import EventKit
import CoreData
import CoreLocation

/// iPhoneのカレンダーとの連携。
/// - 取り込み: その日の予定を、記録の候補として出す
/// - 書き出し: 行った場所を専用の「あしあと」カレンダーに予定として書く
///   (TimeTree はこのカレンダーを取り込めば表示できる)
@MainActor
final class CalendarSync {
    static let shared = CalendarSync()
    let store = EKEventStore()

    /// 設定のキー(@AppStorage と共有)
    static let importKey = "calendarImportEnabled"
    static let exportKey = "calendarExportEnabled"

    private init() {}

    var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    /// アクセスの許可を求める(許可済みなら true)
    func requestAccess() async -> Bool {
        if hasAccess { return true }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    // MARK: - 取り込み

    /// その日にかかる予定(あしあとが書き出した予定は除く)。終日・場所つきを先に
    func events(on date: Date) -> [EKEvent] {
        guard hasAccess, UserDefaults.standard.bool(forKey: Self.importKey) else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        let own = ashiatoCalendarIdentifier
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: pred)
            .filter { $0.calendar.calendarIdentifier != own }
            .sorted { a, b in
                let sa = (a.location?.isEmpty == false ? 0 : 1) + (a.isAllDay ? 0 : 1)
                let sb = (b.location?.isEmpty == false ? 0 : 1) + (b.isAllDay ? 0 : 1)
                return sa < sb
            }
    }

    /// 予定が複数日にまたがるときの最終日(1日だけなら nil)
    static func lastDay(of event: EKEvent) -> Date? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: event.startDate)
        // 終日の予定は終わりが「最終日の終わり」なので1秒戻して日付を取る
        let lastMoment = event.endDate.addingTimeInterval(-1)
        let last = cal.startOfDay(for: lastMoment)
        return last > start ? last : nil
    }

    // MARK: - 書き出し

    private static let calendarIDKey = "ashiatoCalendarID"
    private var ashiatoCalendarIdentifier: String? {
        UserDefaults.standard.string(forKey: Self.calendarIDKey)
    }

    /// 書き出し先の「あしあと」カレンダー(なければ作る)
    private func ashiatoCalendar() -> EKCalendar? {
        if let id = ashiatoCalendarIdentifier, let c = store.calendar(withIdentifier: id) { return c }
        // 他の端末で作ったものがあれば使う(iCloudカレンダーで同期されるため)
        if let c = store.calendars(for: .event).first(where: { $0.title == "あしあと" && $0.allowsContentModifications }) {
            UserDefaults.standard.set(c.calendarIdentifier, forKey: Self.calendarIDKey)
            return c
        }
        let c = EKCalendar(for: .event, eventStore: store)
        c.title = "あしあと"
        c.cgColor = UIColor(AppPalette.accent).cgColor
        // iCloud があればそこに作る(iPad・Mac・TimeTreeからも見えるように)
        c.source = store.defaultCalendarForNewEvents?.source
            ?? store.sources.first { $0.sourceType == .calDAV }
            ?? store.sources.first { $0.sourceType == .local }
        do {
            try store.saveCalendar(c, commit: true)
            UserDefaults.standard.set(c.calendarIdentifier, forKey: Self.calendarIDKey)
            return c
        } catch {
            return nil
        }
    }

    /// 予定に付ける目印(同じ記録を二重に書かないため。他の端末で書いた分も見つけられる)
    private func marker(for place: Place) -> URL? {
        place.id.flatMap { URL(string: "ashiato://place/\($0.uuidString)") }
    }

    /// この記録を書いた予定を探す
    private func existingEvent(for place: Place, in cal: EKCalendar) -> EKEvent? {
        guard let marker = marker(for: place) else { return nil }
        // 日付を変えた場合にも見つけられるよう、広めの範囲で探す
        let center = place.visitDate ?? Date()
        let c = Calendar.current
        guard let from = c.date(byAdding: .year, value: -3, to: center),
              let to = c.date(byAdding: .year, value: 3, to: center) else { return nil }
        let pred = store.predicateForEvents(withStart: from, end: to, calendars: [cal])
        return store.events(matching: pred).first { $0.url == marker }
    }

    /// 記録を予定として書き出す(日付のない記録は書かない)
    func export(_ place: Place, members: [Member]) {
        guard hasAccess, UserDefaults.standard.bool(forKey: Self.exportKey),
              let cal = ashiatoCalendar() else { return }
        let existing = existingEvent(for: place, in: cal)
        guard let start = place.visitDate else {
            if let existing { try? store.remove(existing, span: .thisEvent) }
            return
        }
        let ev = existing ?? EKEvent(eventStore: store)
        ev.calendar = cal
        ev.title = "🐾 \(place.name ?? "")"
        ev.isAllDay = true
        ev.startDate = Calendar.current.startOfDay(for: start)
        ev.endDate = Calendar.current.startOfDay(for: place.visitEndDate ?? start)
        ev.location = place.name
        ev.structuredLocation = {
            let loc = EKStructuredLocation(title: place.name ?? "")
            loc.geoLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
            return loc
        }()
        ev.notes = "あしあとで記録 · 行った人: \(place.whoLabel(members: members))"
        ev.url = marker(for: place)
        try? store.save(ev, span: .thisEvent, commit: true)
    }

    /// 記録を消したときに予定も消す
    func remove(_ place: Place) {
        guard hasAccess, let id = ashiatoCalendarIdentifier,
              let cal = store.calendar(withIdentifier: id),
              let ev = existingEvent(for: place, in: cal) else { return }
        try? store.remove(ev, span: .thisEvent, commit: true)
    }

    /// すべての記録を書き出す(オンにしたときと起動時。共有相手が増やした記録も反映)
    func exportAll(_ places: [Place], members: [Member]) {
        guard hasAccess, UserDefaults.standard.bool(forKey: Self.exportKey) else { return }
        for p in places { export(p, members: members) }
    }
}

// MARK: - 設定画面

struct CalendarSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let places: [Place]
    let members: [Member]

    @AppStorage(CalendarSync.importKey) private var importOn = false
    @AppStorage(CalendarSync.exportKey) private var exportOn = false
    @State private var denied = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: Binding(get: { importOn }, set: { on in setImport(on) })) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("📅 カレンダーの予定を候補に出す").font(.subheadline.bold())
                            Text("日付をタップしたとき、iPhoneのカレンダーのその日の予定から記録できます。泊まりの予定なら帰った日も入ります。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tint(AppPalette.accent)
                } header: { Text("取り込み") }

                Section {
                    Toggle(isOn: Binding(get: { exportOn }, set: { on in setExport(on) })) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("🐾 行った場所をカレンダーに書き出す").font(.subheadline.bold())
                            Text("iPhoneのカレンダーに「あしあと」カレンダーを作り、行った場所を予定として書き込みます。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tint(AppPalette.accent)
                } header: { Text("書き出し") } footer: {
                    Text("TimeTreeで見るには: TimeTreeの設定 →「外部カレンダー」から「あしあと」カレンダーを表示にしてください。")
                }

                if denied {
                    Section {
                        Text("カレンダーへのアクセスが許可されていません。設定 → あしあと → カレンダー で「フルアクセス」を選んでください。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("カレンダー連携")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
        }
    }

    private func setImport(_ on: Bool) {
        guard on else { importOn = false; return }
        Task {
            let ok = await CalendarSync.shared.requestAccess()
            importOn = ok
            denied = !ok
        }
    }

    private func setExport(_ on: Bool) {
        guard on else { exportOn = false; return }
        Task {
            let ok = await CalendarSync.shared.requestAccess()
            exportOn = ok
            denied = !ok
            if ok { CalendarSync.shared.exportAll(places, members: members) }
        }
    }
}
