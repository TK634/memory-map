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

    private var log: TravelLog { PersistenceController.shared.fetchOrCreateLog(in: context) }
    private var members: [Member] { Array(allMembers) }
    private var filtered: [Place] { allPlaces.filter { filter.matches($0, members: members) } }
    private var years: [Int] {
        Array(Set(allPlaces.compactMap { $0.year > 0 ? Int($0.year) : nil })).sorted(by: >)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                mapLayer
                VStack(spacing: 8) {
                    searchBar
                    filterBar
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }
            .navigationTitle("あしあと")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showRanking = true } label: { Image(systemName: "trophy") }
                    Button { showMembers = true } label: { Image(systemName: "person.2") }
                    Button { Task { await prepareShare() } } label: { Image(systemName: "square.and.arrow.up") }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showList = true } label: { Image(systemName: "list.bullet") }
                }
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
    }

    // MARK: - 地図

    private var mapLayer: some View {
        MapReader { proxy in
            Map(position: $camera) {
                ForEach(filtered, id: \.objectID) { p in
                    Annotation(p.name ?? "", coordinate: .init(latitude: p.latitude, longitude: p.longitude)) {
                        PinView(color: p.pinColor(members: members))
                            .onTapGesture { editingPlace = p }
                    }
                }
            }
            .mapStyle(.standard)
            .onTapGesture { screenPoint in
                guard let coord = proxy.convert(screenPoint, from: .local) else { return }
                addCoordinate = coord
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
                    .background(filter.year == nil ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(AppPalette.chrome))
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
            .background(active ? AnyShapeStyle(AppPalette.chrome) : AnyShapeStyle(.regularMaterial))
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

struct PinView: View {
    let color: Color
    var body: some View {
        ZStack {
            Image(systemName: "mappin.circle.fill")
                .font(.title)
                .foregroundStyle(.white, color)
                .shadow(radius: 2, y: 1)
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
