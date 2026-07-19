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
                    // 使い方ヒント+例
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "shoeprints.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(AppPalette.accent.opacity(0.5))
                        Text("行った場所の名前で検索してください")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
                        Spacer()
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
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
