import SwiftUI
import CoreLocation

/// 実績画面: 制県レベル・訪問国・バッジ
struct AchievementsView: View {
    @Environment(\.dismiss) private var dismiss

    let places: [Place]
    let members: [Member]
    let prefRegions: [GeoRegion]
    let countryRegions: [GeoRegion]

    // MARK: - 集計

    private var japanCoords: [CLLocationCoordinate2D] {
        places.filter(\.isJapan).map { .init(latitude: $0.latitude, longitude: $0.longitude) }
    }
    private var abroadCoords: [CLLocationCoordinate2D] {
        places.filter { !$0.isJapan }.map { .init(latitude: $0.latitude, longitude: $0.longitude) }
    }
    private var visitedPrefs: Set<String> {
        GeoRegion.visitedNames(of: prefRegions, coords: japanCoords)
    }
    private var visitedCountries: Set<String> {
        GeoRegion.visitedNames(of: countryRegions, coords: abroadCoords)
    }
    /// 全員で行った場所の数(メンバー2人以上のとき)
    private var togetherCount: Int {
        guard members.count >= 2 else { return 0 }
        let allIDs = Set(members.compactMap(\.id))
        return places.filter { Set($0.visitorIDList) == allIDs }.count
    }

    private struct Badge: Identifiable {
        let id: String
        let icon: String
        let condition: String
        let unlocked: Bool
    }

    private var badges: [Badge] {
        let p = places.count
        let pref = visitedPrefs.count
        let c = visitedCountries.count
        return [
            .init(id: "はじめてのあしあと", icon: "shoeprints.fill", condition: "最初の記録をつける", unlocked: p >= 1),
            .init(id: "あしあと10", icon: "10.circle.fill", condition: "10か所記録する", unlocked: p >= 10),
            .init(id: "あしあと30", icon: "30.circle.fill", condition: "30か所記録する", unlocked: p >= 30),
            .init(id: "あしあと100", icon: "flame.fill", condition: "100か所記録する", unlocked: p >= 100),
            .init(id: "制県スタート", icon: "map.fill", condition: "3都道府県に行く", unlocked: pref >= 3),
            .init(id: "制県の旅人", icon: "signpost.right.fill", condition: "10都道府県に行く", unlocked: pref >= 10),
            .init(id: "制県マスター", icon: "crown.fill", condition: "25都道府県に行く", unlocked: pref >= 25),
            .init(id: "全県制覇", icon: "trophy.fill", condition: "47都道府県すべてに行く", unlocked: pref >= 47),
            .init(id: "はじめての海外", icon: "airplane", condition: "海外に1か国行く", unlocked: c >= 1),
            .init(id: "世界を歩く", icon: "globe.asia.australia.fill", condition: "5か国に行く", unlocked: c >= 5),
            .init(id: "世界の旅人", icon: "globe.europe.africa.fill", condition: "10か国に行く", unlocked: c >= 10),
            .init(id: "みんなの思い出", icon: "heart.fill", condition: "全員で5か所行く", unlocked: togetherCount >= 5),
        ]
    }

    // MARK: - UI

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    seikenCard
                    worldCard
                    badgeGrid
                }
                .padding()
            }
            .background(Color(hex: "FFF8EF"))
            .navigationTitle("実績")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
        }
    }

    /// 制県レベルカード
    private var seikenCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("制県レベル", systemImage: "map.fill")
                    .font(.headline)
                Spacer()
                Text("\(visitedPrefs.count)")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppPalette.accent)
                Text("/ 47").font(.subheadline).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(visitedPrefs.count), total: 47)
                .tint(AppPalette.accent)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                ForEach(prefRegions) { pref in
                    Text(pref.id.replacingOccurrences(of: "県", with: "")
                            .replacingOccurrences(of: "府", with: ""))
                        .font(.system(size: 11, weight: .bold))
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(visitedPrefs.contains(pref.id)
                                    ? AnyShapeStyle(AppPalette.accent)
                                    : AnyShapeStyle(Color.gray.opacity(0.15)),
                                    in: Capsule())
                        .foregroundStyle(visitedPrefs.contains(pref.id) ? .white : .secondary)
                }
            }
        }
        .padding()
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
    }

    /// 世界のあしあとカード
    private var worldCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("世界のあしあと", systemImage: "globe.asia.australia.fill")
                    .font(.headline)
                Spacer()
                Text("\(visitedCountries.count)")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppPalette.chrome)
                Text("か国").font(.subheadline).foregroundStyle(.secondary)
            }
            if visitedCountries.isEmpty {
                Text("海外のあしあとを記録すると、ここに国が増えていきます。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                FlowChips(items: visitedCountries.sorted())
            }
        }
        .padding()
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
    }

    /// バッジ一覧
    private var badgeGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("バッジ", systemImage: "rosette").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 14) {
                ForEach(badges) { badge in
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(badge.unlocked ? AppPalette.accent : Color.gray.opacity(0.15))
                                .frame(width: 58, height: 58)
                            Image(systemName: badge.unlocked ? badge.icon : "lock.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(badge.unlocked ? .white : Color.gray.opacity(0.5))
                        }
                        Text(badge.id)
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text(badge.condition)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
        .padding()
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
    }
}

/// 折り返しチップ(訪問国の表示用)
private struct FlowChips: View {
    let items: [String]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6)], spacing: 6) {
            ForEach(items, id: \.self) { name in
                Text(name)
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(AppPalette.chrome.opacity(0.12), in: Capsule())
            }
        }
    }
}
