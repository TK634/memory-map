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
    @State private var addCoordinate: CLLocationCoordinate2D?
    @State private var editingPlace: Place?
    @State private var showMembers = false
    @State private var showRanking = false
    @State private var showList = false
    @State private var showShare = false
    @State private var shareInfo: (CKShare, CKContainer)?
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var showHelp = false
    @State private var showOnboarding = false
    @State private var replayTutorial = false
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

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
                searchBar
                filterBar
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
        }
        .overlay(alignment: .bottom) { bottomBar }
        .onAppear {
            if !hasSeenOnboarding { showOnboarding = true }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView {
                hasSeenOnboarding = true
                showOnboarding = false
            }
        }
        .sheet(isPresented: $showHelp, onDismiss: {
            if replayTutorial { replayTutorial = false; showOnboarding = true }
        }) {
            HelpView { replayTutorial = true }
        }
        .sheet(item: $addCoordinate) { coord in
            AddEditPlaceView(log: log, coordinate: coord, place: nil, members: members)
        }
        .sheet(item: $editingPlace) { place in
            AddEditPlaceView(log: log,
                             coordinate: .init(latitude: place.latitude, longitude: place.longitude),
                             place: place, members: members)
        }
        .sheet(isPresented: $showMembers) { MembersView(log: log) }
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
        }
    }

    // MARK: - フローティングメニューバー

    private var bottomBar: some View {
        HStack(spacing: 0) {
            barButton("list.bullet", "一覧") { showList = true }
            barButton("trophy.fill", "ランキング") { showRanking = true }
            // 中央の共有ボタンだけ大きく強調
            Button { Task { await prepareShare() } } label: {
                VStack(spacing: 3) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(AppPalette.accent, in: Circle())
                        .shadow(color: AppPalette.accent.opacity(0.4), radius: 5, y: 2)
                    Text("共有")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppPalette.chrome)
                }
                .frame(maxWidth: .infinity)
            }
            .offset(y: -8)
            barButton("person.2.fill", "メンバー") { showMembers = true }
            barButton("questionmark.circle.fill", "使い方") { showHelp = true }
        }
        .padding(.horizontal, 6)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    private func barButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
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
        MapReader { proxy in
            Map(position: $camera) {
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
            .onTapGesture { screenPoint in
                guard let coord = proxy.convert(screenPoint, from: .local) else { return }
                addCoordinate = coord
            }
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
    }

    // MARK: - 検索バー

    private var searchBar: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("場所を検索(例:京都、パリ)", text: $searchText)
                    .onSubmit { runSearch() }
                if !searchText.isEmpty {
                    Button { searchText = ""; searchResults = [] } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))

            if !searchResults.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(searchResults.prefix(5), id: \.self) { item in
                        Button {
                            let c = item.placemark.coordinate
                            searchResults = []; searchText = ""
                            camera = .region(MKCoordinateRegion(center: c, latitudeDelta: 1.5, longitudeDelta: 1.5))
                            addCoordinate = c
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name ?? "").font(.subheadline).foregroundStyle(.primary)
                                Text(item.placemark.title ?? "").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8).padding(.horizontal, 12)
                        }
                        Divider()
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func runSearch() {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = searchText
        MKLocalSearch(request: req).start { resp, _ in
            searchResults = resp?.mapItems ?? []
        }
    }

    // MARK: - フィルターバー

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("すべて", active: filter.who == .all) { filter.who = .all; filter.whoOnly = false }
                ForEach(members, id: \.objectID) { m in
                    if let id = m.id {
                        chip(m.displayName, dot: m.color, active: filter.who == .member(id)) {
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
                    chip(r.label, active: filter.region == r) { filter.region = r }
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

    private func chip(_ label: String, dot: Color? = nil, active: Bool, action: @escaping () -> Void) -> some View {
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
        } catch {
            print("共有の準備に失敗: \(error)")
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

extension CLLocationCoordinate2D: Identifiable {
    public var id: String { "\(latitude),\(longitude)" }
}

extension MKCoordinateRegion {
    func toRegion() -> MKCoordinateRegion { self }
    init(center: CLLocationCoordinate2D, latitudeDelta: CLLocationDegrees, longitudeDelta: CLLocationDegrees) {
        self.init(center: center, span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta))
    }
}
