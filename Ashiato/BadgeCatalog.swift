import Foundation

/// バッジの定義と解放判定。実績画面と祝福演出の両方から使う
struct BadgeDef: Identifiable {
    let id: String
    let icon: String
    let condition: String
    /// 解放条件
    let isUnlocked: (BadgeStats) -> Bool
}

/// 判定に必要な集計値
struct BadgeStats {
    let placeCount: Int
    let prefCount: Int
    let countryCount: Int
    let visitedPrefs: Set<String>
    let togetherCount: Int
    let commentCount: Int
    let photoCount: Int
    let seasonCount: Int
    let yearCount: Int
    let longTripCount: Int
}

enum BadgeCatalog {
    static let all: [BadgeDef] = [
        // 記録数
        .init(id: "はじめてのあしあと", icon: "shoeprints.fill", condition: "最初の記録をつける") { $0.placeCount >= 1 },
        .init(id: "あしあと10", icon: "10.circle.fill", condition: "10か所記録する") { $0.placeCount >= 10 },
        .init(id: "あしあと30", icon: "30.circle.fill", condition: "30か所記録する") { $0.placeCount >= 30 },
        .init(id: "あしあと50", icon: "50.circle.fill", condition: "50か所記録する") { $0.placeCount >= 50 },
        .init(id: "あしあと100", icon: "flame.fill", condition: "100か所記録する") { $0.placeCount >= 100 },
        // 制県
        .init(id: "制県スタート", icon: "map.fill", condition: "3都道府県に行く") { $0.prefCount >= 3 },
        .init(id: "制県の旅人", icon: "signpost.right.fill", condition: "10都道府県に行く") { $0.prefCount >= 10 },
        .init(id: "制県マスター", icon: "crown.fill", condition: "25都道府県に行く") { $0.prefCount >= 25 },
        .init(id: "全県制覇", icon: "trophy.fill", condition: "47都道府県すべてに行く") { $0.prefCount >= 47 },
        // 場所もの
        .init(id: "北の大地", icon: "snowflake", condition: "北海道に行く") { $0.visitedPrefs.contains("北海道") },
        .init(id: "南国のあしあと", icon: "sun.max.fill", condition: "沖縄県に行く") { $0.visitedPrefs.contains("沖縄県") },
        .init(id: "三大都市めぐり", icon: "building.2.fill", condition: "東京・大阪・愛知に行く") {
            $0.visitedPrefs.isSuperset(of: ["東京都", "大阪府", "愛知県"])
        },
        // 海外
        .init(id: "はじめての海外", icon: "airplane", condition: "海外に1か国行く") { $0.countryCount >= 1 },
        .init(id: "世界を歩く", icon: "globe.asia.australia.fill", condition: "5か国に行く") { $0.countryCount >= 5 },
        .init(id: "世界の旅人", icon: "globe.europe.africa.fill", condition: "10か国に行く") { $0.countryCount >= 10 },
        // 旅のスタイル
        .init(id: "泊まりの旅", icon: "moon.stars.fill", condition: "2泊以上の旅を記録する") { $0.longTripCount >= 1 },
        .init(id: "春夏秋冬", icon: "leaf.fill", condition: "4つの季節すべてで記録する") { $0.seasonCount >= 4 },
        .init(id: "旅の歴史家", icon: "book.fill", condition: "3つの年の記録をつける") { $0.yearCount >= 3 },
        // ふたり・思い出
        .init(id: "ふたりのはじまり", icon: "heart.circle.fill", condition: "全員で1か所行く") { $0.togetherCount >= 1 },
        .init(id: "みんなの思い出", icon: "heart.fill", condition: "全員で5か所行く") { $0.togetherCount >= 5 },
        .init(id: "ことばのあしあと", icon: "text.bubble.fill", condition: "コメントを10件書く") { $0.commentCount >= 10 },
        .init(id: "おもいでカメラ", icon: "camera.fill", condition: "写真を10枚残す") { $0.photoCount >= 10 },
    ]

    /// Place配列から集計値を作る(国数は呼び出し側で渡す場合に上書き可)
    static func stats(places: [Place], members: [Member],
                      visitedPrefs: Set<String>, countryCount: Int = 0) -> BadgeStats {
        let cal = Calendar.current
        let allIDs = Set(members.compactMap(\.id))
        let together = members.count >= 2
            ? places.filter { Set($0.visitorIDList) == allIDs }.count : 0

        var comments = 0, photos = 0
        for p in places {
            let atts = (p.attachments as? Set<Attachment>) ?? []
            comments += atts.filter { $0.imageData == nil && !($0.comment ?? "").isEmpty }.count
            photos += atts.filter { $0.imageData != nil }.count
        }

        var seasons = Set<Int>()
        for d in places.compactMap(\.visitDate) {
            switch cal.component(.month, from: d) {
            case 3...5: seasons.insert(0)
            case 6...8: seasons.insert(1)
            case 9...11: seasons.insert(2)
            default: seasons.insert(3)
            }
        }

        let longTrips = places.filter { p in
            guard let s = p.visitDate, let e = p.visitEndDate else { return false }
            return (cal.dateComponents([.day], from: s, to: e).day ?? 0) >= 2
        }.count

        return BadgeStats(
            placeCount: places.count,
            prefCount: visitedPrefs.count,
            countryCount: countryCount,
            visitedPrefs: visitedPrefs,
            togetherCount: together,
            commentCount: comments,
            photoCount: photos,
            seasonCount: seasons.count,
            yearCount: Set(places.compactMap { $0.year > 0 ? $0.year : nil }).count,
            longTripCount: longTrips
        )
    }

    static func unlockedIDs(places: [Place], members: [Member],
                            visitedPrefs: Set<String>, countryCount: Int = 0) -> [String] {
        let s = stats(places: places, members: members,
                      visitedPrefs: visitedPrefs, countryCount: countryCount)
        return all.filter { $0.isUnlocked(s) }.map(\.id)
    }
}
