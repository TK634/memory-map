import SwiftUI
import CoreLocation

/// 実績画面: 制県レベル・訪問国・バッジ
struct AchievementsView: View {
    @Environment(\.dismiss) private var dismiss

    let places: [Place]
    let members: [Member]
    let prefRegions: [GeoRegion]
    let countryRegions: [GeoRegion]

    @State private var shareImage: Image?

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

    /// JISコード順(北海道→沖縄)の都道府県
    private static let prefOrder: [String] = [
        "北海道", "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県",
        "茨城県", "栃木県", "群馬県", "埼玉県", "千葉県", "東京都", "神奈川県",
        "新潟県", "富山県", "石川県", "福井県", "山梨県", "長野県", "岐阜県",
        "静岡県", "愛知県", "三重県", "滋賀県", "京都府", "大阪府", "兵庫県",
        "奈良県", "和歌山県", "鳥取県", "島根県", "岡山県", "広島県", "山口県",
        "徳島県", "香川県", "愛媛県", "高知県", "福岡県", "佐賀県", "長崎県",
        "熊本県", "大分県", "宮崎県", "鹿児島県", "沖縄県",
    ]
    private var sortedPrefRegions: [GeoRegion] {
        prefRegions.sorted {
            (Self.prefOrder.firstIndex(of: $0.id) ?? 99) < (Self.prefOrder.firstIndex(of: $1.id) ?? 99)
        }
    }

    private var stats: BadgeStats {
        BadgeCatalog.stats(places: places, members: members,
                           visitedPrefs: visitedPrefs, countryCount: visitedCountries.count)
    }
    private var badges: [(def: BadgeDef, unlocked: Bool)] {
        let s = stats
        return BadgeCatalog.all.map { ($0, $0.isUnlocked(s)) }
    }
    private var commentCount: Int { stats.commentCount }
    private var photoCount: Int { stats.photoCount }
    private var seasonCount: Int { stats.seasonCount }
    private var yearCount: Int { stats.yearCount }
    private var longTripCount: Int { stats.longTripCount }

    // MARK: - UI

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    nextGoalCard
                    seikenCard
                    worldCard
                    badgeGrid
                }
                .padding()
            }
            .background(Color(hex: "FFF8EF"))
            .navigationTitle("実績")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let shareImage {
                        ShareLink(item: shareImage,
                                  preview: SharePreview("あしあと 制県レベル", image: shareImage)) {
                            Label("シェア", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } }
            }
            .onAppear {
                renderShareImage()
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-showAchievements") {
                    print("[実績検証] 制県: \(visitedPrefs.count)/47 -> \(visitedPrefs.sorted())")
                    print("[実績検証] 国: \(visitedCountries.count) -> \(visitedCountries.sorted())")
                    print("[実績検証] 全員の場所: \(togetherCount), コメント: \(commentCount), 写真: \(photoCount), 季節: \(seasonCount), 年数: \(yearCount), 連泊: \(longTripCount)")
                    for b in badges {
                        print("[実績検証] \(b.unlocked ? "✅" : "🔒") \(b.def.id) (\(b.def.condition))")
                    }
                }
                #endif
            }
        }
    }

    /// SNS投稿用のシェア画像を生成
    @MainActor private func renderShareImage() {
        let card = SeikenShareCard(visitedPrefs: visitedPrefs,
                                   prefRegions: prefRegions,
                                   placeCount: places.count,
                                   countryCount: visitedCountries.count)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        if let ui = renderer.uiImage {
            shareImage = Image(uiImage: ui)
        }
    }

    /// 「あと◯」の残り表示(ゴールが近いほどやる気が出る)
    private func remainingText(for badge: BadgeDef) -> String? {
        let s = stats
        let targets: [(String, Int, Int, String)] = [
            ("あしあと10", s.placeCount, 10, "か所"),
            ("あしあと30", s.placeCount, 30, "か所"),
            ("あしあと50", s.placeCount, 50, "か所"),
            ("あしあと100", s.placeCount, 100, "か所"),
            ("制県スタート", s.prefCount, 3, "県"),
            ("制県の旅人", s.prefCount, 10, "県"),
            ("制県マスター", s.prefCount, 25, "県"),
            ("全県制覇", s.prefCount, 47, "県"),
            ("世界を歩く", s.countryCount, 5, "か国"),
            ("世界の旅人", s.countryCount, 10, "か国"),
            ("みんなの思い出", s.togetherCount, 5, "か所"),
            ("ことばのあしあと", s.commentCount, 10, "件"),
            ("おもいでカメラ", s.photoCount, 10, "枚"),
        ]
        guard let t = targets.first(where: { $0.0 == badge.id }) else { return nil }
        let remain = t.2 - t.1
        return remain > 0 ? "あと\(remain)\(t.3)" : nil
    }

    /// 次の目標カード(旅行しない期間もアプリを開く理由をつくる)
    @ViewBuilder
    private var nextGoalCard: some View {
        let nextBadge = badges.first { !$0.unlocked }?.def
        let unvisited = Self.prefOrder.filter { !visitedPrefs.contains($0) }
        VStack(alignment: .leading, spacing: 12) {
            Label("次のあしあと", systemImage: "sparkles")
                .font(.headline)
            if let nextBadge {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(AppPalette.accent.opacity(0.15)).frame(width: 46, height: 46)
                        Image(systemName: nextBadge.icon)
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(AppPalette.accent)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("次は「\(nextBadge.id)」")
                            .font(.subheadline.bold())
                        Text(nextBadge.condition)
                            .font(.caption).foregroundStyle(.secondary)
                        if let remain = remainingText(for: nextBadge) {
                            Text(remain)
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(AppPalette.accent, in: Capsule())
                        }
                    }
                }
            }
            if !unvisited.isEmpty {
                Divider()
                Text("まだあしあとのない場所")
                    .font(.caption.bold()).foregroundStyle(.secondary)
                // 未踏の中から3県を提案(日替わりで変わる)
                let seed = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
                let picks = (0..<min(3, unvisited.count)).map { i in
                    unvisited[(seed &* 7 &+ i &* 17) % unvisited.count]
                }
                HStack(spacing: 8) {
                    ForEach(Array(Set(picks)).sorted(), id: \.self) { name in
                        Text(name)
                            .font(.caption.bold())
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Color.gray.opacity(0.12), in: Capsule())
                    }
                }
                Text("次のおでかけの行き先にどうぞ。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
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
            Text("制覇率 \(Int(Double(visitedPrefs.count) / 47 * 100))%")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                ForEach(sortedPrefRegions) { pref in
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
                ForEach(badges, id: \.def.id) { badge in
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(badge.unlocked ? AppPalette.accent : Color.gray.opacity(0.15))
                                .frame(width: 58, height: 58)
                            Image(systemName: badge.unlocked ? badge.def.icon : "lock.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(badge.unlocked ? .white : Color.gray.opacity(0.5))
                        }
                        Text(badge.def.id)
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text(badge.def.condition)
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

// MARK: - SNSシェア用カード

/// 制県レベルのシェア画像(日本地図の塗り絵+レベル)
struct SeikenShareCard: View {
    let visitedPrefs: Set<String>
    let prefRegions: [GeoRegion]
    let placeCount: Int
    let countryCount: Int

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "shoeprints.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(AppPalette.accent, in: Circle())
                Text("あしあと")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppPalette.chrome)
                Spacer()
                Text("制県レベル")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(visitedPrefs.count)")
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppPalette.accent)
                Text("/ 47 都道府県")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            JapanMiniMap(prefRegions: prefRegions, visited: visitedPrefs)
                .frame(height: 250)
            HStack(spacing: 20) {
                statChip("あしあと", "\(placeCount)")
                statChip("海外", "\(countryCount)か国")
            }
            Text("#あしあと で旅の記録をシェア")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(width: 360)
        .background(
            LinearGradient(colors: [Color(hex: "FFF6EA"), Color(hex: "FFE3C2")],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    private func statChip(_ label: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(label).font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value).font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(AppPalette.chrome)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.white, in: Capsule())
    }
}

/// 47都道府県のミニ塗り絵地図(Canvas描画)
struct JapanMiniMap: View {
    let prefRegions: [GeoRegion]
    let visited: Set<String>

    var body: some View {
        Canvas { ctx, size in
            let lonMin = 122.5, lonMax = 149.5, latMin = 24.0, latMax = 45.8
            // 中緯度の縦横比補正(cos35°≒0.82)
            let spanX = (lonMax - lonMin) * 0.82
            let spanY = latMax - latMin
            let scale = min(size.width / spanX, size.height / spanY)
            let offX = (size.width - spanX * scale) / 2
            let offY = (size.height - spanY * scale) / 2
            func pt(_ c: CLLocationCoordinate2D) -> CGPoint {
                CGPoint(x: offX + (c.longitude - lonMin) * 0.82 * scale,
                        y: offY + (latMax - c.latitude) * scale)
            }
            for region in prefRegions {
                var path = Path()
                for ring in region.polygons {
                    guard let first = ring.first else { continue }
                    path.move(to: pt(first))
                    for c in ring.dropFirst() { path.addLine(to: pt(c)) }
                    path.closeSubpath()
                }
                let fill: Color = visited.contains(region.id)
                    ? AppPalette.accent : Color.gray.opacity(0.22)
                ctx.fill(path, with: .color(fill))
                ctx.stroke(path, with: .color(.white), lineWidth: 0.8)
            }
        }
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
