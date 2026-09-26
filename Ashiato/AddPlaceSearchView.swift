import SwiftUI
import MapKit
import CoreLocation

/// 「登録」ボタンから開く検索シート。
/// 行った場所を検索 → 候補を選ぶと記録画面へ進む。
struct AddPlaceSearchView: View {
    @Environment(\.dismiss) private var dismiss
    /// 候補確定時に呼ばれる(場所名, 座標)
    /// カレンダーで選んだ日(見出し表示用)
    var date: Date? = nil
    var onSelect: (String, CLLocationCoordinate2D) -> Void

    @State private var text = ""
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var nearby: [MKMapItem] = []
    @State private var isLoadingNearby = false
    @State private var locationDenied = false

    /// 検索の例(表示は絵文字付き、検索語は地名だけ)
    private let examples: [(emoji: String, word: String)] = [
        ("⛩️", "京都"), ("🌺", "沖縄"), ("🌲", "軽井沢"), ("🗼", "パリ"), ("🏝️", "ハワイ"),
    ]

    /// 「いまここ」は今日の記録のときだけ(過去の日付では現在地は関係ない)
    private var showsHere: Bool {
        guard let date else { return true }
        return Calendar.current.isDateInToday(date)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppStyle.background
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        hero
                        searchField
                        if results.isEmpty {
                            if showsHere { hereCard }
                            if !nearby.isEmpty {
                                sectionLabel("📍 近くの場所")
                                resultList(nearby)
                            } else if text.isEmpty {
                                sectionLabel("✨ たとえば")
                                exampleChips
                            } else if isSearching {
                                HStack { Spacer(); ProgressView(); Spacer() }.padding(.top, 20)
                            }
                        } else {
                            sectionLabel("🔎 見つかった場所")
                            resultList(results)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 30)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                    }
                }
            }
            .onAppear {
                // 開いた直後に近くの候補を先読み(許可済みなら即座に出る)
                Task { await preloadNearbyIfAuthorized() }
            }
        }
    }

    // MARK: - 部品

    /// 大きな見出し+選んだ日付
    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let date {
                Label(date.jaDateText, systemImage: "calendar")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppPalette.accent)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(AppPalette.accent.opacity(0.12), in: Capsule())
            }
            Text("どこに行った?")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(AppPalette.chrome)
        }
        .padding(.top, 4)
    }

    /// 白いカプセル型の検索欄
    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(AppPalette.accent)
            // 変換確定時だけ値が変わる欄(ローマ字入力の途中で検索が走らない)
            IMETextField(text: $text,
                         placeholder: String(localized: "お店・観光地・街の名前"),
                         returnKey: .search,
                         autoFocus: true,
                         onCommit: runSearch)
                .frame(height: 24)
                .onChange(of: text) { _, newValue in
                    // 入力が止まったら自動で検索(ボタンを押す手間をなくす)
                    searchTask?.cancel()
                    let q = newValue.trimmingCharacters(in: .whitespaces)
                    guard q.count >= 2 else { results = []; return }
                    searchTask = Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        guard !Task.isCancelled else { return }
                        runSearch()
                    }
                }
            if !text.isEmpty {
                Button { text = ""; results = [] } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 15)
        .background(.white, in: Capsule())
        .shadow(color: Color(hex: "C98A4B").opacity(0.14), radius: 14, y: 5)
    }

    /// 「いまここ」カード(オレンジのグラデーション)
    private var hereCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                UIApplication.shared.dismissKeyboard()
                Task { await loadNearby() }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppPalette.accent)
                        .frame(width: 44, height: 44)
                        .background(.white, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("いまここを記録")
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                        Text("近くのお店や公園から選べます")
                            .font(.system(size: 12, weight: .semibold))
                            .opacity(0.9)
                    }
                    .foregroundStyle(.white)
                    Spacer()
                    if isLoadingNearby {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(16)
                .background(AppStyle.accentGradient,
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: AppPalette.accent.opacity(0.3), radius: 12, y: 5)
            }
            .buttonStyle(PressableStyle())

            if locationDenied {
                Text("位置情報の利用がオフです。設定 → あしあと → 位置情報 から許可すると「いまここ」が使えます。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .foregroundStyle(AppPalette.chrome.opacity(0.75))
            .padding(.top, 4)
    }

    /// 絵文字付きの例チップ
    private var exampleChips: some View {
        FlowRow(spacing: 8) {
            ForEach(examples, id: \.word) { ex in
                Button {
                    text = ex.word
                    runSearch()
                } label: {
                    Text("\(ex.emoji) \(ex.word)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppPalette.chrome)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.white, in: Capsule())
                        .shadow(color: Color(hex: "C98A4B").opacity(0.10), radius: 6, y: 2)
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    /// 候補のカード一覧
    private func resultList(_ items: [MKMapItem]) -> some View {
        VStack(spacing: 10) {
            ForEach(items, id: \.self) { item in
                let icon = PlaceCategoryIcon.symbol(for: item)
                Button {
                    onSelect(item.name ?? "", item.placemark.coordinate)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: icon.name)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(icon.color)
                            .frame(width: 44, height: 44)
                            .background(icon.color.opacity(0.14),
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name ?? "")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(AppPalette.chrome)
                                .lineLimit(1)
                            Text(item.placemark.title ?? "")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(AppPalette.accent)
                    }
                    .padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: Color(hex: "C98A4B").opacity(0.08), radius: 8, y: 3)
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    /// 位置情報が既に許可済みなら、開いた瞬間に近くの候補を出しておく
    private func preloadNearbyIfAuthorized() async {
        guard showsHere else { return }
        guard CLLocationManager().authorizationStatus == .authorizedWhenInUse
                || CLLocationManager().authorizationStatus == .authorizedAlways else { return }
        await loadNearby()
    }

    /// 現在地の周辺スポットを読み込む
    private func loadNearby() async {
        isLoadingNearby = true
        defer { isLoadingNearby = false }
        guard let coord = await LocationManager.shared.requestCurrentLocation() else {
            locationDenied = LocationManager.shared.isDenied
            return
        }
        locationDenied = false
        nearby = await NearbySearch.spots(around: coord)
    }

    private func runSearch() {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = text
        isSearching = true
        MKLocalSearch(request: req).start { resp, _ in
            isSearching = false
            results = resp?.mapItems ?? []
        }
    }
}
