import SwiftUI
import MapKit
import CoreData
import CloudKit

struct ContentView: View {
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(sortDescriptors: [SortDescriptor(\Place.createdAt, order: .reverse)])
    private var allPlaces: FetchedResults<Place>

    @FetchRequest(sortDescriptors: [SortDescriptor(\Member.createdAt)])
    private var allMembers: FetchedResults<Member>

    @State private var filter = PlaceFilter()
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(center: .init(latitude: 36.2, longitude: 138.2),
                           latitudeDelta: 12, longitudeDelta: 12)
        .toRegion()
    )
    /// 登録待ちの場所(検索候補で確定した名前と座標をセットで持つ)
    struct PendingPlace: Identifiable {
        let id = UUID()
        let name: String
        let coord: CLLocationCoordinate2D
    }
    @State private var addPlace: PendingPlace?
    @State private var editingPlace: Place?
    @State private var showMembers = false
    @State private var showRanking = false
    @State private var showList = false
    @State private var showShare = false
    @State private var shareInfo: (CKShare, CKContainer)?
    @State private var shareError: String?
    @State private var showAddSearch = false
    @State private var pendingAdd: (name: String, coord: CLLocationCoordinate2D)?
    @State private var showHelp = false
    @State private var showOnboarding = false
    @State private var replayTutorial = false
    @State private var showAchievements = false
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("memoryCardDismissedDate") private var memoryCardDismissedDate = ""

    /// 「1年前の今日」の思い出
    private var todaysMemories: [Place] {
        MemoryLane.todaysMemories(from: allPlaces.map { $0 })
    }

    @StateObject private var celebration = CelebrationCenter.shared

    // アニメ調フラット地図の塗り分けデータ(起動後に非同期読み込み)
    @State private var countryRegions: [GeoRegion] = []
    @State private var prefRegions: [GeoRegion] = []

    private var log: TravelLog { PersistenceController.shared.fetchOrCreateLog(in: context) }
    private var members: [Member] { Array(allMembers) }
    private var filtered: [Place] { allPlaces.filter { filter.matches($0, members: members) } }
    private var years: [Int] {
        Array(Set(allPlaces.compactMap { $0.year > 0 ? Int($0.year) : nil })).sorted(by: >)
    }

    var body: some View {
        ZStack(alignment: .top) {
            mapLayer
            VStack(spacing: 8) {
                header
                filterBar
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                MemoryCardView(memories: todaysMemories,
                               onTap: { p in
                                   camera = .region(MKCoordinateRegion(
                                       center: .init(latitude: p.latitude, longitude: p.longitude),
                                       latitudeDelta: 1.2, longitudeDelta: 1.2))
                                   editingPlace = p
                               },
                               dismissedDate: $memoryCardDismissedDate)
                    .padding(.horizontal, 14)
                bottomBar
            }
        }
        .onAppear {
            if !hasSeenOnboarding { showOnboarding = true }
            // 今日の思い出があれば翌朝9時に通知(旅行しない日も開く理由をつくる)
            MemoryLane.scheduleDailyReminder(places: allPlaces.map { $0 })
            #if DEBUG
            DemoSeeder.seedIfRequested(context: context, log: log)
            if ProcessInfo.processInfo.arguments.contains("-demoCelebration") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showOnboarding = false
                    celebration.pending = [.prefecture(name: "京都府", count: 8)]
                }
            }
            if ProcessInfo.processInfo.arguments.contains("-openFirstPlace") {
                // 記録画面の見た目確認用: 最初のピンの編集画面を開く
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showOnboarding = false
                    editingPlace = allPlaces.first { $0.name == (ProcessInfo.processInfo.arguments.contains("-openPhotoPlace") ? "那覇" : "東京") } ?? allPlaces.first
                }
            }
            if DemoSeeder.shouldShowAchievements {
                // GeoJSON読み込みを待ってから実績を開く(検証・スクショ用)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    showOnboarding = false
                    showAchievements = true
                }
            }
            #endif
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(onFinish: {
                hasSeenOnboarding = true
                showOnboarding = false
            }, onInvite: {
                Task { await prepareShare() }
            })
        }
        .sheet(isPresented: $showHelp, onDismiss: {
            if replayTutorial { replayTutorial = false; showOnboarding = true }
        }) {
            HelpView { replayTutorial = true }
        }
        .sheet(isPresented: $showAddSearch, onDismiss: {
            // 検索シートで候補が確定していたら記録画面を開く
            if let p = pendingAdd {
                pendingAdd = nil
                camera = .region(MKCoordinateRegion(center: p.coord,
                                                    latitudeDelta: 1.5, longitudeDelta: 1.5))
                addPlace = PendingPlace(name: p.name, coord: p.coord)
            }
        }) {
            AddPlaceSearchView { name, coord in
                pendingAdd = (name, coord)
                showAddSearch = false
            }
        }
        .sheet(item: $addPlace) { pending in
            AddEditPlaceView(log: log, coordinate: pending.coord, place: nil, members: members,
                             initialName: pending.name)
        }
        .alert("共有できませんでした", isPresented: Binding(
            get: { shareError != nil }, set: { if !$0 { shareError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shareError ?? "")
        }
        .sheet(item: $editingPlace) { place in
            AddEditPlaceView(log: log,
                             coordinate: .init(latitude: place.latitude, longitude: place.longitude),
                             place: place, members: members)
        }
        .sheet(isPresented: $showMembers) { MembersView(log: log) }
        .sheet(isPresented: $showAchievements) {
            AchievementsView(places: allPlaces.map { $0 }, members: members,
                             prefRegions: prefRegions, countryRegions: countryRegions)
        }
        .sheet(isPresented: $showRanking) {
            RankingView(places: allPlaces.map { $0 }, members: members, filter: filter)
        }
        .sheet(isPresented: $showList) {
            PlacesListView(places: filtered, members: members) { p in
                showList = false
                camera = .region(MKCoordinateRegion(
                    center: .init(latitude: p.latitude, longitude: p.longitude),
                    latitudeDelta: 1.2, longitudeDelta: 1.2))
            }
        }
        .sheet(isPresented: $showShare) {
            if let info = shareInfo {
                CloudSharingView(share: info.0, container: info.1)
            }
        }
        // 記録が増えたら実績の解放を判定して祝う
        .onChange(of: allPlaces.count) { _, _ in
            celebration.check(places: allPlaces.map { $0 }, members: members,
                              prefRegions: prefRegions)
        }
        .onChange(of: prefRegions.count) { _, _ in
            celebration.check(places: allPlaces.map { $0 }, members: members,
                              prefRegions: prefRegions)
        }
        .overlay {
            if let kind = celebration.pending.first {
                CelebrationOverlay(kind: kind) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        if !celebration.pending.isEmpty { celebration.pending.removeFirst() }
                    }
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: - オリジナルヘッダー(ロゴ)

    private var header: some View {
        HStack {
            HStack(spacing: 7) {
                Image(systemName: "shoeprints.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(7)
                    .background(AppPalette.accent, in: Circle())
                Text("あしあと")
                    .font(.title3.bold())
                    .foregroundStyle(AppPalette.chrome)
            }
            .padding(.leading, 8).padding(.trailing, 14).padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            Spacer()
            Button { Task { await prepareShare() } } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppPalette.chrome)
                    .frame(width: 38, height: 38)
                    .background(.regularMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            }
            Button { showHelp = true } label: {
                Image(systemName: "questionmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppPalette.chrome)
                    .frame(width: 38, height: 38)
                    .background(.regularMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            }
        }
    }

    // MARK: - フローティングメニューバー

    private var bottomBar: some View {
        HStack(spacing: 0) {
            barButton("list.bullet", "一覧") { showList = true }
            barButton("trophy.fill", "ランキング") { showRanking = true }
            // 中央の「登録」ボタンだけ大きく強調
            Button { showAddSearch = true } label: {
                VStack(spacing: 3) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(AppPalette.accent, in: Circle())
                        .shadow(color: AppPalette.accent.opacity(0.4), radius: 5, y: 2)
                    Text("登録")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppPalette.chrome)
                }
                .frame(maxWidth: .infinity)
            }
            .offset(y: -8)
            barButton("person.2.fill", "メンバー") { showMembers = true }
            barButton("rosette", "実績") { showAchievements = true }
        }
        .padding(.horizontal, 6)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    private func barButton(_ icon: String, _ label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                Text(label)
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(AppPalette.chrome)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 地図

    private var mapLayer: some View {
            // 回転・傾きは無効(北固定)。方位磁針が出ずヘッダーとも被らない
            Map(position: $camera, interactionModes: [.pan, .zoom]) {
                // 1. 海: フラットな青で全面を覆う
                ForEach(Array(GeoData.oceanBands.enumerated()), id: \.offset) { _, band in
                    MapPolygon(coordinates: band)
                        .foregroundStyle(GeoData.ocean)
                }
                // 2. 世界の国々(パステルで塗り分け)
                ForEach(countryRegions) { region in
                    ForEach(Array(region.polygons.enumerated()), id: \.offset) { _, poly in
                        MapPolygon(coordinates: poly)
                            .foregroundStyle(region.color)
                            .stroke(.white, lineWidth: 1)
                    }
                }
                // 3. 日本の都道府県(パステルで塗り分け)
                ForEach(prefRegions) { region in
                    ForEach(Array(region.polygons.enumerated()), id: \.offset) { _, poly in
                        MapPolygon(coordinates: poly)
                            .foregroundStyle(region.color)
                            .stroke(.white, lineWidth: 1.5)
                    }
                }
                // 4. あしあとピン
                ForEach(filtered, id: \.objectID) { p in
                    Annotation(p.name ?? "", coordinate: .init(latitude: p.latitude, longitude: p.longitude)) {
                        PinView(color: p.pinColor(members: members))
                            .onTapGesture { editingPlace = p }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted,
                                pointsOfInterest: .excludingAll, showsTraffic: false))
            .task {
                // GeoJSONの読み込みはバックグラウンドで(起動をブロックしない)
                if countryRegions.isEmpty {
                    let countries = await Task.detached { GeoData.load("countries") }.value
                    let prefs = await Task.detached { GeoData.load("prefectures") }.value
                    countryRegions = countries
                    prefRegions = prefs
                }
            }
    }

    // MARK: - フィルターバー

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("すべて", active: filter.who == .all) { filter.who = .all; filter.whoOnly = false }
                ForEach(members, id: \.objectID) { m in
                    if let id = m.id {
                        chip(raw: m.displayName, dot: m.color, active: filter.who == .member(id)) {
                            filter.who = .member(id)
                        }
                    }
                }
                if members.count > 1 {
                    chip("全員一緒", dot: AppPalette.together, active: filter.who == .together) {
                        filter.who = .together; filter.whoOnly = false
                    }
                    if case .member(let id) = filter.who, let m = members.first(where: { $0.id == id }) {
                        chip("\(m.displayName)だけ", dot: m.color, active: filter.whoOnly) {
                            filter.whoOnly.toggle()
                        }
                    }
                }
                Divider().frame(height: 20)
                ForEach(RegionFilter.allCases) { r in
                    chip(raw: r.label, active: filter.region == r) { filter.region = r }
                }
                Divider().frame(height: 20)
                Menu {
                    Button("すべての年") { filter.year = nil }
                    ForEach(years, id: \.self) { y in Button("\(String(y))年") { filter.year = y } }
                    Button("年未設定") { filter.year = 0 }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                        Text(filter.year == nil ? "年" : (filter.year == 0 ? "未設定" : "\(String(filter.year!))年"))
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(filter.year == nil ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(AppPalette.accent))
                    .foregroundStyle(filter.year == nil ? .primary : Color.white)
                    .clipShape(Capsule())
                }
            }
        }
    }

    /// メンバー名など翻訳対象外の文字列用
    private func chip(raw label: String, dot: Color? = nil, active: Bool,
                      action: @escaping () -> Void) -> some View {
        chip(LocalizedStringKey(label), dot: dot, active: active, action: action)
    }

    private func chip(_ label: LocalizedStringKey, dot: Color? = nil, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
                Text(label)
            }
            .font(.caption.bold())
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(active ? AnyShapeStyle(AppPalette.accent) : AnyShapeStyle(.regularMaterial))
            .foregroundStyle(active ? Color.white : .primary)
            .clipShape(Capsule())
        }
    }

    // MARK: - 共有

    private func prepareShare() async {
        do {
            shareInfo = try await PersistenceController.shared.getOrCreateShare(for: log)
            showShare = true
            // 共有する=相手の動きを知りたいタイミングなので、ここで通知許可を求める
            await NotificationManager.shared.requestAuthorization()
        } catch {
            shareError = """
            iCloudの共有リンクを作成できませんでした。
            共有には、iCloudにサインインした実機が必要です。\
            (シミュレータや、開発用の署名がない状態では利用できません)

            詳細: \(error.localizedDescription)
            """
        }
    }
}

// MARK: - ピン表示

/// 白い丸バッジ+足あとマーク。アプリ名「あしあと」にちなんだピン
struct PinView: View {
    let color: Color
    var body: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 30, height: 30)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
            Circle()
                .stroke(color.opacity(0.4), lineWidth: 2)
                .frame(width: 30, height: 30)
            Image(systemName: "shoeprints.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
        }
    }
}

// MARK: - 小物

extension MKCoordinateRegion {
    func toRegion() -> MKCoordinateRegion { self }
    init(center: CLLocationCoordinate2D, latitudeDelta: CLLocationDegrees, longitudeDelta: CLLocationDegrees) {
        self.init(center: center, span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta))
    }
}
