import SwiftUI
import CoreData
import MapKit

// MARK: - 旅(複数の場所を、日ごと・行った順にまとめる)

extension Trip {
    private var cal: Calendar { Calendar.current }

    /// 表示名(未入力なら「旅」)
    var displayName: String {
        let n = (name ?? "").trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? String(localized: "旅") : n
    }

    /// 旅のメンバー(memberIDs はメンバーUUIDのカンマ区切り)
    var memberIDList: [UUID] {
        get { (memberIDs ?? "").split(separator: ",").compactMap { UUID(uuidString: String($0)) } }
        set { memberIDs = newValue.map(\.uuidString).joined(separator: ",") }
    }

    func members(in all: [Member]) -> [Member] {
        let ids = Set(memberIDList)
        return all.filter { m in m.id.map(ids.contains) ?? false }
    }

    /// この旅のメンバーが行った場所か。同じ期間に別々の旅をしていても、
    /// 他の人だけが行った場所は入れない(行った人が未設定の記録は入れる)
    func isForMembers(_ p: Place) -> Bool {
        // 削除済みのメンバーは数えない(残っていると判定がずれる)
        let valid = Set(((log?.members as? Set<Member>) ?? []).compactMap(\.id))
        let tripIDs = Set(memberIDList).intersection(valid)
        let placeIDs = Set(p.visitorIDList)
        return tripIDs.isEmpty || placeIDs.isEmpty || !tripIDs.isDisjoint(with: placeIDs)
    }

    /// この旅に入っている場所
    var placeList: [Place] {
        ((places as? Set<Place>) ?? []).filter { !$0.isDeleted }
    }

    /// 場所がどの日に属するか(行った日。日付が無ければ旅の初日)
    func day(of p: Place) -> Date {
        cal.startOfDay(for: p.visitDate ?? startDate ?? Date())
    }

    /// 行った順(日付 → 旅の中の順番 → 登録順)
    var orderedPlaces: [Place] {
        placeList.sorted { a, b in
            let da = day(of: a), db = day(of: b)
            if da != db { return da < db }
            if a.tripOrder != b.tripOrder { return a.tripOrder < b.tripOrder }
            return (a.createdAt ?? .distantPast) < (b.createdAt ?? .distantPast)
        }
    }

    /// 旅の日(期間の日 + 期間外に動かした場所の日)
    var days: [Date] {
        var set = Set<Date>()
        if let s = startDate {
            var d = cal.startOfDay(for: s)
            let e = cal.startOfDay(for: endDate ?? s)
            while d <= e {
                set.insert(d)
                guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
                d = next
            }
        }
        placeList.forEach { set.insert(day(of: $0)) }
        return set.sorted()
    }

    func places(on day: Date) -> [Place] {
        orderedPlaces.filter { self.day(of: $0) == day }
    }

    /// 旅に場所を加える。その日に泊まった宿(泊まりの記録)は日の最後に、
    /// 観光地などは宿の前に入れる(宿に着くのはふつうその日の最後のため)
    func append(_ p: Place) {
        let d = day(of: p)
        var list = places(on: d).filter { $0 != p }
        if p.visitEndDate != nil {
            list.append(p)
        } else {
            let firstStay = list.firstIndex { $0.visitEndDate != nil } ?? list.count
            list.insert(p, at: firstStay)
        }
        p.trip = self
        for (i, x) in list.enumerated() { x.tripOrder = Int32(i) }
    }

    /// その日に「宿を発つ」泊まりの記録(前の日以前に着いて、この日に発つ)
    func departures(on d: Date) -> [Place] {
        orderedPlaces.filter { p in
            guard let e = p.visitEndDate else { return false }
            return day(of: p) < d && cal.startOfDay(for: e) == d
        }
    }

    /// その日も「続けて泊まっている」泊まりの記録(連泊の中日)
    func stayingOver(on d: Date) -> [Place] {
        orderedPlaces.filter { p in
            guard let e = p.visitEndDate else { return false }
            return day(of: p) < d && cal.startOfDay(for: e) > d
        }
    }

    /// 家に帰った日(旅の最終日)
    func isHomecoming(_ d: Date) -> Bool {
        guard let s = startDate, let e = endDate, !cal.isDate(s, inSameDayAs: e) else { return false }
        return cal.isDate(d, inSameDayAs: e)
    }

    /// その日の最後に追加するときの順番
    func nextOrder(on day: Date) -> Int32 {
        (places(on: day).map(\.tripOrder).max() ?? -1) + 1
    }

    /// 期間の表記(例: 2026年10月3日〜10月5日)
    var periodText: String {
        guard let s = startDate else { return String(localized: "期間未設定") }
        let e = endDate ?? s
        if cal.isDate(s, inSameDayAs: e) { return s.jaDateText }
        let locale = AppRegion.preferredLocale
        let sameYear = cal.component(.year, from: s) == cal.component(.year, from: e)
        let end = sameYear ? e.formatted(.dateTime.month().day().locale(locale)) : e.jaDateText
        return "\(s.jaDateText)〜\(end)"
    }

    var nights: Int {
        guard let s = startDate, let e = endDate else { return 0 }
        return max(0, cal.dateComponents([.day], from: cal.startOfDay(for: s), to: cal.startOfDay(for: e)).day ?? 0)
    }

    var coverPhoto: Attachment? { orderedPlaces.lazy.compactMap(\.coverPhoto).first }

    /// 新しい旅を作る。期間内にあって、まだどの旅にも入っていない「メンバーが行った」記録は自動で入れる
    @discardableResult
    static func make(in context: NSManagedObjectContext, log: TravelLog,
                     start: Date, end: Date, name: String, memberIDs: [UUID]) -> Trip {
        let cal = Calendar.current
        let s = cal.startOfDay(for: min(start, end))
        let e = cal.startOfDay(for: max(start, end))
        let t = Trip(context: context)
        t.id = UUID()
        t.createdAt = Date()
        t.name = name
        t.startDate = s
        t.endDate = e
        t.memberIDList = memberIDs
        t.log = log
        // 記録帳と同じストアへ(共有中の記録帳なら共有ストアに入れないと保存できない)
        context.assign([t], toStoreOf: log)

        let req = NSFetchRequest<Place>(entityName: "Place")
        let afterEnd = cal.date(byAdding: .day, value: 1, to: e) ?? e
        req.predicate = NSPredicate(format: "trip == nil AND log == %@ AND visitDate >= %@ AND visitDate < %@",
                                    log, s as NSDate, afterEnd as NSDate)
        let found = ((try? context.fetch(req)) ?? []).sorted {
            (($0.visitDate ?? .distantPast), ($0.createdAt ?? .distantPast))
                < (($1.visitDate ?? .distantPast), ($1.createdAt ?? .distantPast))
        }
        for p in found where t.isForMembers(p) {
            t.append(p)
        }
        try? context.save()
        return t
    }

    /// 日付がこの旅の期間内か
    func covers(_ date: Date?) -> Bool {
        guard let date, let s = startDate else { return false }
        let d = cal.startOfDay(for: date)
        return d >= cal.startOfDay(for: s) && d <= cal.startOfDay(for: endDate ?? s)
    }

    /// 旅の画面以外(カレンダーなど)から追加した場所も、期間とメンバーが合う旅が
    /// ちょうど1つあれば、その日の最後に入れる(候補が複数なら迷わせないよう入れない)
    static func autoJoin(_ p: Place, in context: NSManagedObjectContext) {
        guard p.trip == nil, let log = p.log, let date = p.visitDate else { return }
        let trips = ((log.trips as? Set<Trip>) ?? []).filter { !$0.isDeleted && $0.covers(date) && $0.isForMembers(p) }
        guard trips.count == 1, let t = trips.first else { return }
        t.append(p)
    }

    /// 期間内にあって、この旅にまだ入っていない記録(メンバーが行ったもの)
    func suggestions() -> [Place] {
        guard let log else { return [] }
        return ((log.places as? Set<Place>) ?? [])
            .filter { !$0.isDeleted && $0.trip != self && covers($0.visitDate) && isForMembers($0) }
            .sorted { ($0.visitDate ?? .distantPast) < ($1.visitDate ?? .distantPast) }
    }

    /// 「タカ・ハナ」のような、だれの旅かの表記(全員なら「全員」)
    func whoText(in all: [Member]) -> String {
        let ms = members(in: all)
        if ms.isEmpty || (all.count > 1 && ms.count == all.count) { return String(localized: "全員") }
        return ms.map(\.displayName).joined(separator: "・")
    }

    /// 既定の名前。メンバー全員ではない旅は「ハナの…」とだれの旅かを付ける
    /// (同じ期間に別々の旅をしても、名前で見分けられるように)
    static func defaultName(start: Date, end: Date, memberNames: [String]) -> String {
        let base = defaultName(start: start, end: end)
        guard !memberNames.isEmpty else { return base }
        return String(localized: "\(memberNames.joined(separator: "・"))の\(base)")
    }

    /// 既定の名前(例: 10月3日〜5日の旅)
    static func defaultName(start: Date, end: Date) -> String {
        let cal = Calendar.current
        let locale = AppRegion.preferredLocale
        let s = min(start, end), e = max(start, end)
        let sText = s.formatted(.dateTime.month().day().locale(locale))
        if cal.isDate(s, inSameDayAs: e) { return String(localized: "\(sText)の旅") }
        let sameMonth = cal.component(.month, from: s) == cal.component(.month, from: e)
        let eText = sameMonth ? e.formatted(.dateTime.day().locale(locale))
                              : e.formatted(.dateTime.month().day().locale(locale))
        return String(localized: "\(sText)〜\(eText)の旅")
    }
}

/// 「だれの旅?」のメンバー選択
struct TripMemberChips: View {
    let members: [Member]
    @Binding var selected: Set<UUID>

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(members, id: \.objectID) { m in
                if let id = m.id {
                    let on = selected.contains(id)
                    Button {
                        if on { selected.remove(id) } else { selected.insert(id) }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(m.color).frame(width: 10, height: 10)
                            Text(m.displayName).font(.subheadline.bold())
                            if on { Image(systemName: "checkmark").font(.caption.bold()) }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .foregroundStyle(on ? .white : AppPalette.chrome)
                        .background(on ? m.color : Color.gray.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// 横に並べて、はみ出したら折り返す
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            maxX = max(maxX, x - spacing)
            rowH = max(rowH, s.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

/// 番号つきの丸(行った順)
struct RouteNumberBadge: View {
    let number: Int
    var size: CGFloat = 26
    var body: some View {
        Text("\(number)")
            .font(.system(size: size * 0.5, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(AppPalette.accent, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
    }
}

// MARK: - 旅の一覧

struct TripListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [SortDescriptor(\Trip.startDate, order: .reverse)])
    private var trips: FetchedResults<Trip>
    let log: TravelLog
    let members: [Member]

    @State private var path: [Trip] = []
    @State private var showNew = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if trips.isEmpty {
                    VStack(spacing: 10) {
                        Text("🧳").font(.system(size: 44))
                        Text("まだ旅がありません")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppPalette.chrome)
                        Text("旅の名前と期間を決めて、行った場所を日ごとに順番に記録できます。カレンダーの「旅をまとめて記録」からも作れます。")
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button { showNew = true } label: {
                            Label("新しい旅をつくる", systemImage: "plus")
                                .font(.subheadline.bold())
                                .padding(.horizontal, 18).padding(.vertical, 10)
                                .background(AppPalette.accent, in: Capsule())
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(trips) { t in
                        NavigationLink(value: t) { TripRow(trip: t, members: members) }
                    }
                }
            }
            .navigationTitle("旅")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Trip.self) { t in
                TripDetailView(trip: t, log: log, members: members)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { showNew = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("新しい旅をつくる")
                }
            }
            .sheet(isPresented: $showNew) {
                NewTripSheet(members: members) { start, end, name, ids in
                    let t = Trip.make(in: context, log: log, start: start, end: end, name: name, memberIDs: ids)
                    path.append(t)
                }
            }
        }
    }
}

private struct TripRow: View {
    @ObservedObject var trip: Trip
    let members: [Member]
    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let cover = trip.coverPhoto {
                    PhotoThumb(attachment: cover, pixel: 160)
                } else {
                    Text("🧳").font(.system(size: 24))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(hex: "FFF6EA"))
                }
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(trip.displayName)
                    .font(.subheadline.bold()).foregroundStyle(AppPalette.chrome)
                Text(trip.periodText)
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text("\(trip.placeList.count)か所")
                        .font(.caption2.bold()).foregroundStyle(AppPalette.accent)
                    if members.count > 1 {
                        HStack(spacing: 3) {
                            ForEach(trip.members(in: members), id: \.objectID) { m in
                                Circle().fill(m.color).frame(width: 7, height: 7)
                            }
                            Text(trip.whoText(in: members))
                        }
                        .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 新しい旅

struct NewTripSheet: View {
    @Environment(\.dismiss) private var dismiss
    let members: [Member]
    var initialStart: Date = Date()
    var initialEnd: Date = Date()
    var onCreate: (Date, Date, String, [UUID]) -> Void

    @State private var name = ""
    @State private var start = Date()
    @State private var end = Date()
    @State private var memberIDs: Set<UUID> = []

    var body: some View {
        NavigationStack {
            Form {
                Section("旅の名前") {
                    TextField(suggestedName, text: $name)
                }
                Section {
                    DatePicker("出発した日", selection: $start, displayedComponents: .date)
                        .onChange(of: start) { _, s in if end < s { end = s } }
                    DatePicker("帰った日", selection: $end, in: start..., displayedComponents: .date)
                } header: {
                    Text("期間")
                }
                if members.count > 1 {
                    Section {
                        TripMemberChips(members: members, selected: $memberIDs)
                            .padding(.vertical, 4)
                    } header: {
                        Text("だれの旅?")
                    } footer: {
                        Text("この期間にすでに記録した場所のうち、選んだ人が行った場所が自動でこの旅に入ります。同じ期間に別々の旅をしていても混ざりません。")
                    }
                }
            }
            .navigationTitle("新しい旅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("つくる") {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        onCreate(start, end, n.isEmpty ? suggestedName : n, Array(memberIDs))
                        UserDefaults.standard.set(memberIDs.map(\.uuidString), forKey: "lastTripMemberIDs")
                        dismiss()
                    }
                    .bold()
                    .disabled(members.count > 1 && memberIDs.isEmpty)
                }
            }
            .onAppear {
                start = initialStart
                end = max(initialStart, initialEnd)
                // 前回の旅のメンバーを初期値に。ただし前回の選択にこのiPhoneの「自分」が
                // 入っていなければ全員(自分が入っていない旅を既定にしない)
                let valid = Set(members.compactMap(\.id))
                let last = Set((UserDefaults.standard.stringArray(forKey: "lastTripMemberIDs") ?? [])
                    .compactMap(UUID.init(uuidString:))).intersection(valid)
                let me = UserDefaults.standard.string(forKey: "myMemberID").flatMap(UUID.init(uuidString:))
                    .flatMap { valid.contains($0) ? $0 : nil }
                if last.isEmpty || (me != nil && !last.contains(me!)) {
                    memberIDs = valid
                } else {
                    memberIDs = last
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// 名前を空のまま作ったときの名前(全員の旅でなければ「ハナの…」)
    private var suggestedName: String {
        let chosen = members.filter { m in m.id.map(memberIDs.contains) ?? false }
        let names = (members.count > 1 && chosen.count < members.count) ? chosen.map(\.displayName) : []
        return Trip.defaultName(start: start, end: end, memberNames: names)
    }
}

// MARK: - 旅の詳細(日ごとの場所 + 道のりの地図)

struct TripDetailView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var trip: Trip
    let log: TravelLog
    let members: [Member]
    /// シートで開いたとき(カレンダーから作った直後)は「閉じる」を出す
    var showsCloseButton = false

    @State private var nameText = ""
    @State private var memberSelection: Set<UUID> = []
    @State private var version = 0
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var addRequest: AddRequest?
    @State private var pendingAdd: PendingTripPlace?
    @State private var addPlace: PendingTripPlace?
    @State private var editingPlace: Place?
    @State private var showPeriod = false
    @State private var showDeleteConfirm = false

    struct AddRequest: Identifiable {
        let id = UUID()
        let day: Date
    }
    struct PendingTripPlace: Identifiable {
        let id = UUID()
        let name: String
        let coord: CLLocationCoordinate2D
        let day: Date
        let endDate: Date?
    }

    var body: some View {
        let _ = version
        let ordered = trip.orderedPlaces
        List {
            Section {
                TextField("旅の名前", text: $nameText)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppPalette.chrome)
                    .submitLabel(.done)
                    .onSubmit(saveName)
                Button { showPeriod = true } label: {
                    HStack {
                        Label(trip.periodText, systemImage: "calendar")
                        Spacer()
                        Text(trip.nights > 0 ? "\(trip.nights)泊\(trip.nights + 1)日" : "日帰り")
                            .font(.caption.bold()).foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.chrome)
                }
                if members.count > 1 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("だれの旅?").font(.caption.bold()).foregroundStyle(.secondary)
                        TripMemberChips(members: members, selected: $memberSelection)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section {
                routeMap(ordered)
                    .frame(height: 240)
                    .listRowInsets(EdgeInsets())
            } footer: {
                if ordered.count > 1 { Text("行った順に線でつなぎました。並べ替えは右上の「編集」から。") }
            }

            let allDays = trip.days
            let emptyDays = allDays.filter {
                trip.places(on: $0).isEmpty && trip.departures(on: $0).isEmpty
                    && trip.stayingOver(on: $0).isEmpty && !trip.isHomecoming($0)
            }
            let tripPhotos = ordered.flatMap(\.photoAttachments)
            if !tripPhotos.isEmpty {
                Section {
                    NavigationLink {
                        TripAlbumView(trip: trip)
                    } label: {
                        HStack(spacing: 10) {
                            HStack(spacing: -10) {
                                ForEach(Array(tripPhotos.prefix(4).enumerated()), id: \.offset) { _, att in
                                    PhotoThumb(attachment: att, pixel: 120)
                                        .frame(width: 38, height: 38)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white, lineWidth: 2))
                                }
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text("この旅のアルバム").font(.subheadline.bold()).foregroundStyle(AppPalette.chrome)
                                Text("\(tripPhotos.count)枚の写真を、行った順に")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            ForEach(Array(allDays.enumerated()).filter { !emptyDays.contains($0.element) }, id: \.element) { i, day in
                Section {
                    ForEach(trip.departures(on: day), id: \.objectID) { p in
                        stayNote("🏨", String(localized: "「\(p.name ?? "")」を発つ"))
                    }
                    ForEach(trip.stayingOver(on: day), id: \.objectID) { p in
                        stayNote("🌙", String(localized: "「\(p.name ?? "")」に連泊"))
                    }
                    ForEach(trip.places(on: day), id: \.objectID) { p in
                        placeRow(p, number: (ordered.firstIndex(of: p) ?? 0) + 1)
                            .swipeActions {
                                Button("旅から外す") { remove(p) }.tint(.orange)
                            }
                    }
                    .onMove { from, to in move(on: day, from: from, to: to) }
                    if trip.isHomecoming(day) {
                        stayNote("🏠", String(localized: "家に帰った日"))
                    }
                    Button { addRequest = AddRequest(day: day) } label: {
                        Label("この日に行った場所を追加", systemImage: "plus.circle.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(AppPalette.accent)
                    }
                } header: {
                    Text("\(i + 1)日目  \(day.formatted(.dateTime.month().day().weekday(.abbreviated).locale(AppRegion.preferredLocale)))")
                }
            }

            if !emptyDays.isEmpty {
                Section {
                    FlowLayout(spacing: 8) {
                        ForEach(emptyDays, id: \.self) { day in
                            Button { addRequest = AddRequest(day: day) } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus").font(.caption2.bold())
                                    Text("\((allDays.firstIndex(of: day) ?? 0) + 1)日目 \(day.formatted(.dateTime.month().day().locale(AppRegion.preferredLocale)))")
                                        .font(.caption.bold())
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .foregroundStyle(AppPalette.accent)
                                .background(AppPalette.accent.opacity(0.1), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text(allDays.count == emptyDays.count ? "行った場所を追加" : "まだ記録のない日")
                } footer: {
                    Text("日付をタップして、その日に行った場所を追加します。")
                }
            }

            let others = trip.suggestions()
            if !others.isEmpty {
                Section {
                    ForEach(others, id: \.objectID) { p in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name ?? "").font(.subheadline.bold())
                                Text([p.visitDate?.formatted(.dateTime.month().day().locale(AppRegion.preferredLocale)),
                                      p.whoLabel(members: members),
                                      p.trip.map { String(localized: "「\($0.displayName)」に入っています") }]
                                        .compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(p.trip == nil ? "入れる" : "移す") { addToTrip(p) }
                                .font(.subheadline.bold())
                                .buttonStyle(.borderless)
                                .tint(AppPalette.accent)
                        }
                    }
                } header: {
                    Text("この期間のほかの記録")
                } footer: {
                    Text("旅の期間中で、この旅のメンバーが行った記録です。旅に入れると、行った順の最後に加わります。")
                }
            }

            Section {
                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    Label("この旅を削除", systemImage: "trash")
                }
            } footer: {
                Text("旅を削除しても、行った場所の記録は残ります。")
            }
        }
        .navigationTitle(trip.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { saveName(); dismiss() }
                }
            }
            ToolbarItem(placement: .primaryAction) { EditButton() }
        }
        .onAppear {
            nameText = trip.name ?? ""
            memberSelection = Set(trip.memberIDList)
        }
        .onChange(of: memberSelection) { _, ids in
            guard Set(trip.memberIDList) != ids else { return }
            trip.memberIDList = Array(ids)
            try? context.save()
        }
        .onDisappear(perform: saveName)
        // 場所の追加・編集・削除(共有相手の変更も含む)を反映する
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange,
                                                        object: context)) { _ in
            version &+= 1
        }
        .onChange(of: ordered.count, initial: true) { _, _ in fitMap(ordered) }
        // 検索で場所を選んだら、記録画面(写真・ひとことなど)を開く
        .sheet(item: $addRequest, onDismiss: {
            if let p = pendingAdd {
                pendingAdd = nil
                addPlace = p
            }
        }) { req in
            AddPlaceSearchView(date: req.day) { name, coord, endDate in
                pendingAdd = PendingTripPlace(name: name, coord: coord, day: req.day, endDate: endDate)
                addRequest = nil
            }
        }
        .sheet(item: $addPlace) { p in
            AddEditPlaceView(log: log, coordinate: p.coord, place: nil, members: members,
                             initialName: p.name, initialDate: p.day, initialEndDate: p.endDate,
                             trip: trip)
        }
        .sheet(item: $editingPlace) { p in
            AddEditPlaceView(log: log,
                             coordinate: .init(latitude: p.latitude, longitude: p.longitude),
                             place: p, members: members)
        }
        .sheet(isPresented: $showPeriod) { periodSheet }
        .confirmationDialog("この旅を削除しますか?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                context.delete(trip)
                try? context.save()
                dismiss()
            }
            Button("やめる", role: .cancel) {}
        } message: {
            Text("行った場所の記録は残ります。共有している場合は、相手の画面からも旅が消えます。")
        }
    }

    // MARK: 地図

    @ViewBuilder
    private func routeMap(_ ordered: [Place]) -> some View {
        if ordered.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "map")
                    .font(.system(size: 30))
                    .foregroundStyle(AppPalette.accent.opacity(0.6))
                Text("場所を追加すると、ここに道のりが表示されます")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(hex: "FFF6EA"))
        } else {
            let coords = ordered.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            Map(position: $mapPosition, interactionModes: [.pan, .zoom]) {
                if coords.count > 1 {
                    MapPolyline(coordinates: coords)
                        .stroke(AppPalette.accent,
                                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: [2, 7]))
                }
                ForEach(Array(ordered.enumerated()), id: \.element.objectID) { i, p in
                    Annotation(p.name ?? "", coordinate: coords[i]) {
                        RouteNumberBadge(number: i + 1)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        }
    }

    /// 場所が1か所だけだと自動では拡大しすぎるため、周りが分かる広さにする
    private func fitMap(_ ordered: [Place]) {
        if ordered.count == 1, let p = ordered.first {
            mapPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.4, longitudeDelta: 0.4)))
        } else {
            mapPosition = .automatic
        }
    }

    // MARK: 行

    private func placeRow(_ p: Place, number: Int) -> some View {
        Button { editingPlace = p } label: {
            HStack(spacing: 12) {
                RouteNumberBadge(number: number, size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name ?? "")
                        .font(.subheadline.bold()).foregroundStyle(.primary)
                    Text(rowDetail(p))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let cover = p.coverPhoto {
                    PhotoThumb(attachment: cover, pixel: 120)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)   // List の中だと文字までアクセント色になるため
    }

    /// 宿を発つ・連泊・帰宅などの、番号の付かない説明の行
    private func stayNote(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text(icon).frame(width: 24)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
        .moveDisabled(true)
    }

    /// 「全員一緒 · 泊まり(〜7/11) · 写真5枚」のような1行の説明
    private func rowDetail(_ p: Place) -> String {
        var parts = [p.whoLabel(members: members)]
        if let e = p.visitEndDate {
            let until = e.formatted(.dateTime.month().day().locale(AppRegion.preferredLocale))
            parts.append(String(localized: "泊まり(\(until)に発つ)"))
        }
        let n = p.photoAttachments.count
        if n > 0 { parts.append(String(localized: "写真\(n)枚")) }
        return parts.joined(separator: " · ")
    }

    // MARK: 期間の変更

    private var periodSheet: some View {
        PeriodSheet(start: trip.startDate ?? Date(), end: trip.endDate ?? trip.startDate ?? Date()) { s, e in
            let cal = Calendar.current
            trip.startDate = cal.startOfDay(for: s)
            trip.endDate = cal.startOfDay(for: e)
            try? context.save()
        }
    }

    // MARK: 操作

    private func saveName() {
        let n = nameText.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != trip.name else { return }
        trip.name = n
        try? context.save()
    }

    private func addToTrip(_ p: Place) {
        trip.append(p)
        try? context.save()
    }

    private func remove(_ p: Place) {
        p.trip = nil
        try? context.save()
    }

    /// その日の中で並べ替える
    private func move(on day: Date, from: IndexSet, to: Int) {
        var list = trip.places(on: day)
        list.move(fromOffsets: from, toOffset: to)
        for (i, p) in list.enumerated() { p.tripOrder = Int32(i) }
        try? context.save()
    }
}

private struct PeriodSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var start: Date
    @State var end: Date
    var onSave: (Date, Date) -> Void

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("出発した日", selection: $start, displayedComponents: .date)
                    .onChange(of: start) { _, s in if end < s { end = s } }
                DatePicker("帰った日", selection: $end, in: start..., displayedComponents: .date)
            }
            .navigationTitle("旅の期間")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { onSave(start, end); dismiss() }.bold()
                }
            }
        }
        .presentationDetents([.medium])
    }
}
