import SwiftUI
import MapKit

/// 「登録」ボタンから開く検索シート。
/// 行った場所を検索 → 候補を選ぶと記録画面へ進む。
struct AddPlaceSearchView: View {
    @Environment(\.dismiss) private var dismiss
    /// 候補確定時に呼ばれる(場所名, 座標)
    var onSelect: (String, CLLocationCoordinate2D) -> Void

    @State private var text = ""
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false
    @State private var nearby: [MKMapItem] = []
    @State private var isLoadingNearby = false
    @State private var locationDenied = false
    @FocusState private var focused: Bool

    private let examples = ["京都", "沖縄", "軽井沢", "パリ", "ハワイ"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 検索欄
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("行った場所を検索", text: $text)
                        .focused($focused)
                        .submitLabel(.search)
                        .onSubmit(runSearch)
                    if !text.isEmpty {
                        Button { text = ""; results = [] } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .padding(.top, 8)

                if results.isEmpty {
                    // 「いまここ」+ 近くの候補 + 検索例
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // いまここボタン(日常のおでかけをワンタップで記録)
                            Button {
                                Task { await loadNearby() }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "location.fill")
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 40, height: 40)
                                        .background(AppPalette.accent, in: Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("いまここを記録")
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.primary)
                                        Text("現在地の近くのお店や公園から選べます")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if isLoadingNearby {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(12)
                                .background(
                                    LinearGradient(colors: [Color(hex: "FFF6EA"), Color(hex: "FFEBD3")],
                                                   startPoint: .leading, endPoint: .trailing),
                                    in: RoundedRectangle(cornerRadius: 16)
                                )
                            }
                            .buttonStyle(.plain)

                            if locationDenied {
                                Text("位置情報の利用がオフです。設定 → あしあと → 位置情報 から許可すると「いまここ」が使えます。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }

                            // 近くの候補
                            if !nearby.isEmpty {
                                Text("近くの場所")
                                    .font(.caption.bold()).foregroundStyle(.secondary)
                                VStack(spacing: 0) {
                                    ForEach(nearby, id: \.self) { item in
                                        Button {
                                            onSelect(item.name ?? "", item.placemark.coordinate)
                                        } label: {
                                            HStack(spacing: 12) {
                                                Image(systemName: "mappin.circle.fill")
                                                    .font(.title3).foregroundStyle(AppPalette.accent)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(item.name ?? "")
                                                        .font(.subheadline.bold())
                                                        .foregroundStyle(.primary)
                                                    Text(item.placemark.title ?? "")
                                                        .font(.caption).foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                }
                                                Spacer()
                                            }
                                            .padding(.vertical, 9)
                                        }
                                        .buttonStyle(.plain)
                                        Divider()
                                    }
                                }
                            } else {
                                // 検索例
                                Text("検索してさがす")
                                    .font(.caption.bold()).foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    ForEach(examples, id: \.self) { ex in
                                        Button {
                                            text = ex
                                            runSearch()
                                        } label: {
                                            Text(ex)
                                                .font(.caption.bold())
                                                .padding(.horizontal, 12).padding(.vertical, 7)
                                                .background(AppPalette.accent.opacity(0.12), in: Capsule())
                                                .foregroundStyle(AppPalette.accent)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 14)
                    }
                } else {
                    // 候補一覧
                    List(results, id: \.self) { item in
                        Button {
                            onSelect(item.name ?? "", item.placemark.coordinate)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(AppPalette.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name ?? "")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.primary)
                                    Text(item.placemark.title ?? "")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("行った場所を登録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
            }
            .onAppear { focused = true }
        }
    }

    /// 現在地の周辺スポットを読み込む
    private func loadNearby() async {
        isLoadingNearby = true
        defer { isLoadingNearby = false }
        focused = false
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
