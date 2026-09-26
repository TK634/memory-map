import Foundation

/// バッジの定義と解放判定。実績画面と祝福演出の両方から使う
struct BadgeDef: Identifiable {
    let id: String
    let icon: String
    let condition: String
    let category: BadgeCategory
    /// 解放条件
    let isUnlocked: (BadgeStats) -> Bool
    /// 進み具合(いま・目標・単位)。数で決まるバッジだけ持つ
    var progress: ((BadgeStats) -> (current: Int, goal: Int, unit: String))? = nil
}

/// 実績画面での並びと見出し
enum BadgeCategory: String, CaseIterable {
    case footprints = "🐾 あしあと"
    case seiken = "🗾 制県"
    case area = "🏯 地方・名所"
    case world = "🌏 世界"
    case style = "🧳 旅のスタイル"
    case together = "💞 ふたり・思い出"
}

/// 判定に必要な集計値
struct BadgeStats {
    let placeCount: Int
    let prefCount: Int
    let countryCount: Int
    let visitedPrefs: Set<String>
    let memberCount: Int
    let togetherCount: Int
    let soloCount: Int
    let commentCount: Int
    let photoCount: Int
    let reactionCount: Int
    let seasonCount: Int
    let yearCount: Int
    let longTripCount: Int
    let maxNights: Int
    let maxMonthsInOneYear: Int
    let maxPlacesInOneMonth: Int
    let weekendCount: Int
    let hasNewYear: Bool
    let hasChristmas: Bool
}

enum BadgeCatalog {

    // MARK: - 地方の区分

    static let regions: [(name: String, prefs: [String])] = [
        ("東北", ["青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県"]),
        ("関東", ["茨城県", "栃木県", "群馬県", "埼玉県", "千葉県", "東京都", "神奈川県"]),
        ("中部", ["新潟県", "富山県", "石川県", "福井県", "山梨県", "長野県", "岐阜県", "静岡県", "愛知県"]),
        ("近畿", ["三重県", "滋賀県", "京都府", "大阪府", "兵庫県", "奈良県", "和歌山県"]),
        ("中国", ["鳥取県", "島根県", "岡山県", "広島県", "山口県"]),
        ("四国", ["徳島県", "香川県", "愛媛県", "高知県"]),
        ("九州・沖縄", ["福岡県", "佐賀県", "長崎県", "熊本県", "大分県", "宮崎県", "鹿児島県", "沖縄県"]),
    ]

    // MARK: - 定義を作る補助

    /// 数が目標に届いたら解放されるバッジ
    private static func count(_ id: String, _ icon: String, _ condition: String,
                              _ category: BadgeCategory, goal: Int, unit: String,
                              _ value: @escaping (BadgeStats) -> Int) -> BadgeDef {
        BadgeDef(id: id, icon: icon, condition: condition, category: category,
                 isUnlocked: { value($0) >= goal },
                 progress: { (value($0), goal, unit) })
    }

    /// 条件を満たしたら解放されるバッジ
    private static func flag(_ id: String, _ icon: String, _ condition: String,
                             _ category: BadgeCategory,
                             _ test: @escaping (BadgeStats) -> Bool) -> BadgeDef {
        BadgeDef(id: id, icon: icon, condition: condition, category: category, isUnlocked: test)
    }

    /// 決まった県をすべて訪れたら解放されるバッジ
    private static func prefs(_ id: String, _ icon: String, _ condition: String,
                              _ category: BadgeCategory, _ names: [String]) -> BadgeDef {
        BadgeDef(id: id, icon: icon, condition: condition, category: category,
                 isUnlocked: { $0.visitedPrefs.isSuperset(of: names) },
                 progress: { s in (names.filter(s.visitedPrefs.contains).count, names.count, "県") })
    }

    // MARK: - バッジ一覧

    static let all: [BadgeDef] = {
        var list: [BadgeDef] = [
            // 🐾 あしあと(記録数)
            count("はじめてのあしあと", "shoeprints.fill", "最初の記録をつける", .footprints, goal: 1, unit: "か所") { $0.placeCount },
            count("あしあと10", "10.circle.fill", "10か所記録する", .footprints, goal: 10, unit: "か所") { $0.placeCount },
            count("あしあと30", "30.circle.fill", "30か所記録する", .footprints, goal: 30, unit: "か所") { $0.placeCount },
            count("あしあと50", "50.circle.fill", "50か所記録する", .footprints, goal: 50, unit: "か所") { $0.placeCount },
            count("あしあと100", "flame.fill", "100か所記録する", .footprints, goal: 100, unit: "か所") { $0.placeCount },
            count("あしあと200", "bolt.fill", "200か所記録する", .footprints, goal: 200, unit: "か所") { $0.placeCount },
            count("あしあと300", "star.fill", "300か所記録する", .footprints, goal: 300, unit: "か所") { $0.placeCount },
            count("あしあと500", "sparkles", "500か所記録する", .footprints, goal: 500, unit: "か所") { $0.placeCount },

            // 🗾 制県
            count("制県スタート", "map.fill", "3都道府県に行く", .seiken, goal: 3, unit: "県") { $0.prefCount },
            count("制県ルーキー", "figure.walk", "5都道府県に行く", .seiken, goal: 5, unit: "県") { $0.prefCount },
            count("制県の旅人", "signpost.right.fill", "10都道府県に行く", .seiken, goal: 10, unit: "県") { $0.prefCount },
            count("制県ベテラン", "backpack.fill", "20都道府県に行く", .seiken, goal: 20, unit: "県") { $0.prefCount },
            count("制県マスター", "crown.fill", "25都道府県に行く", .seiken, goal: 25, unit: "県") { $0.prefCount },
            count("制県エキスパート", "medal.fill", "30都道府県に行く", .seiken, goal: 30, unit: "県") { $0.prefCount },
            count("制県レジェンド", "rosette", "40都道府県に行く", .seiken, goal: 40, unit: "県") { $0.prefCount },
            count("全県制覇", "trophy.fill", "47都道府県すべてに行く", .seiken, goal: 47, unit: "県") { $0.prefCount },

            // 🏯 地方・名所
            prefs("北の大地", "snowflake", "北海道に行く", .area, ["北海道"]),
            prefs("南国のあしあと", "sun.max.fill", "沖縄県に行く", .area, ["沖縄県"]),
            prefs("三大都市めぐり", "building.2.fill", "東京・大阪・愛知に行く", .area, ["東京都", "大阪府", "愛知県"]),
            prefs("古都めぐり", "building.columns.fill", "京都・奈良に行く", .area, ["京都府", "奈良県"]),
            prefs("富士山のふもと", "mountain.2.fill", "山梨・静岡に行く", .area, ["山梨県", "静岡県"]),
            prefs("日本の端から端へ", "arrow.left.and.right", "北海道と沖縄の両方に行く", .area, ["北海道", "沖縄県"]),
        ]
        // 各地方の制覇
        let regionIcons = ["東北": "leaf.fill", "関東": "tram.fill", "中部": "mountain.2.fill",
                           "近畿": "building.columns.fill", "中国": "water.waves",
                           "四国": "figure.hiking", "九州・沖縄": "sun.haze.fill"]
        for r in regions {
            list.append(prefs("\(r.name)制覇", regionIcons[r.name] ?? "map.fill",
                              "\(r.name)地方のすべての県に行く", .area, r.prefs))
        }
        list += [
            // 🌏 世界
            count("はじめての海外", "airplane", "海外に1か国行く", .world, goal: 1, unit: "か国") { $0.countryCount },
            count("パスポートの常連", "airplane.departure", "3か国に行く", .world, goal: 3, unit: "か国") { $0.countryCount },
            count("世界を歩く", "globe.asia.australia.fill", "5か国に行く", .world, goal: 5, unit: "か国") { $0.countryCount },
            count("世界の旅人", "globe.europe.africa.fill", "10か国に行く", .world, goal: 10, unit: "か国") { $0.countryCount },
            count("地球人", "globe.americas.fill", "20か国に行く", .world, goal: 20, unit: "か国") { $0.countryCount },
            count("世界一周", "globe", "30か国に行く", .world, goal: 30, unit: "か国") { $0.countryCount },

            // 🧳 旅のスタイル
            count("泊まりの旅", "moon.stars.fill", "2泊以上の旅を記録する", .style, goal: 1, unit: "回") { $0.longTripCount },
            count("旅好き", "suitcase.fill", "2泊以上の旅を5回記録する", .style, goal: 5, unit: "回") { $0.longTripCount },
            count("大冒険", "tent.fill", "5泊以上の旅を記録する", .style, goal: 5, unit: "泊") { $0.maxNights },
            count("長期旅行", "suitcase.rolling.fill", "10泊以上の旅を記録する", .style, goal: 10, unit: "泊") { $0.maxNights },
            count("春夏秋冬", "leaf.fill", "4つの季節すべてで記録する", .style, goal: 4, unit: "季節") { $0.seasonCount },
            count("旅の歴史家", "book.fill", "3つの年の記録をつける", .style, goal: 3, unit: "年") { $0.yearCount },
            count("5年日記", "books.vertical.fill", "5つの年の記録をつける", .style, goal: 5, unit: "年") { $0.yearCount },
            count("10年のあしあと", "clock.arrow.circlepath", "10の年の記録をつける", .style, goal: 10, unit: "年") { $0.yearCount },
            count("月イチおでかけ", "calendar", "同じ年の6か月で記録する", .style, goal: 6, unit: "か月") { $0.maxMonthsInOneYear },
            count("毎月のあしあと", "calendar.badge.checkmark", "同じ年の12か月すべてで記録する", .style, goal: 12, unit: "か月") { $0.maxMonthsInOneYear },
            count("おでかけ上手", "figure.walk.motion", "1か月に5か所記録する", .style, goal: 5, unit: "か所") { $0.maxPlacesInOneMonth },
            count("おでかけマスター", "hare.fill", "1か月に10か所記録する", .style, goal: 10, unit: "か所") { $0.maxPlacesInOneMonth },
            count("週末の旅人", "sun.and.horizon.fill", "土日の記録を10件つける", .style, goal: 10, unit: "件") { $0.weekendCount },
            flag("初詣", "sparkle", "1月1〜3日に記録する", .style) { $0.hasNewYear },
            flag("聖夜のおでかけ", "gift.fill", "12月24・25日に記録する", .style) { $0.hasChristmas },

            // 💞 ふたり・思い出
            count("ふたりのはじまり", "heart.circle.fill", "全員で1か所行く", .together, goal: 1, unit: "か所") { $0.togetherCount },
            count("みんなの思い出", "heart.fill", "全員で5か所行く", .together, goal: 5, unit: "か所") { $0.togetherCount },
            count("なかよし", "person.2.fill", "全員で10か所行く", .together, goal: 10, unit: "か所") { $0.togetherCount },
            count("最高のパートナー", "heart.text.square.fill", "全員で30か所行く", .together, goal: 30, unit: "か所") { $0.togetherCount },
            flag("ひとり旅", "figure.walk.circle.fill", "メンバーのひとりだけで行った場所を記録する", .together) {
                $0.memberCount >= 2 && $0.soloCount >= 1
            },
            count("ことばのあしあと", "text.bubble.fill", "ひとことを10件書く", .together, goal: 10, unit: "件") { $0.commentCount },
            count("語り部", "quote.bubble.fill", "ひとことを50件書く", .together, goal: 50, unit: "件") { $0.commentCount },
            count("思い出の作家", "pencil.and.scribble", "ひとことを100件書く", .together, goal: 100, unit: "件") { $0.commentCount },
            count("おもいでカメラ", "camera.fill", "写真を10枚残す", .together, goal: 10, unit: "枚") { $0.photoCount },
            count("写真家", "camera.aperture", "写真を50枚残す", .together, goal: 50, unit: "枚") { $0.photoCount },
            count("アルバム職人", "photo.stack.fill", "写真を100枚残す", .together, goal: 100, unit: "枚") { $0.photoCount },
            count("はじめてのスタンプ", "face.smiling.inverse", "スタンプを1回押す", .together, goal: 1, unit: "回") { $0.reactionCount },
            count("スタンプ職人", "hands.clap.fill", "スタンプを50回押す", .together, goal: 50, unit: "回") { $0.reactionCount },
        ]
        return list
    }()

    // MARK: - 集計

    /// Place配列から集計値を作る(国数は呼び出し側で渡す)
    static func stats(places: [Place], members: [Member],
                      visitedPrefs: Set<String>, countryCount: Int = 0) -> BadgeStats {
        let cal = Calendar.current
        let allIDs = Set(members.compactMap(\.id))
        let together = members.count >= 2
            ? places.filter { Set($0.visitorIDList) == allIDs }.count : 0
        let solo = places.filter { $0.visitorIDList.count == 1 }.count

        var comments = 0, photos = 0, reactions = 0
        for p in places {
            let atts = (p.attachments as? Set<Attachment>) ?? []
            comments += atts.filter { $0.imageData == nil && !($0.comment ?? "").isEmpty }.count
            photos += atts.filter { $0.imageData != nil }.count
            reactions += ((p.reactions as? Set<Reaction>) ?? []).count
        }

        let dates = places.compactMap(\.visitDate)
        var seasons = Set<Int>()
        var monthsByYear: [Int: Set<Int>] = [:]
        var placesByMonth: [String: Int] = [:]
        var weekend = 0
        var newYear = false, christmas = false
        for d in dates {
            let y = cal.component(.year, from: d)
            let m = cal.component(.month, from: d)
            let day = cal.component(.day, from: d)
            switch m {
            case 3...5: seasons.insert(0)
            case 6...8: seasons.insert(1)
            case 9...11: seasons.insert(2)
            default: seasons.insert(3)
            }
            monthsByYear[y, default: []].insert(m)
            placesByMonth["\(y)-\(m)", default: 0] += 1
            let wd = cal.component(.weekday, from: d)
            if wd == 1 || wd == 7 { weekend += 1 }
            if m == 1 && day <= 3 { newYear = true }
            if m == 12 && (day == 24 || day == 25) { christmas = true }
        }

        var longTrips = 0, maxNights = 0
        for p in places {
            guard let s = p.visitDate, let e = p.visitEndDate else { continue }
            let n = cal.dateComponents([.day], from: cal.startOfDay(for: s),
                                       to: cal.startOfDay(for: e)).day ?? 0
            if n >= 2 { longTrips += 1 }
            maxNights = max(maxNights, n)
        }

        return BadgeStats(
            placeCount: places.count,
            prefCount: visitedPrefs.count,
            countryCount: countryCount,
            visitedPrefs: visitedPrefs,
            memberCount: members.count,
            togetherCount: together,
            soloCount: solo,
            commentCount: comments,
            photoCount: photos,
            reactionCount: reactions,
            seasonCount: seasons.count,
            yearCount: Set(places.compactMap { $0.year > 0 ? $0.year : nil }).count,
            longTripCount: longTrips,
            maxNights: maxNights,
            maxMonthsInOneYear: monthsByYear.values.map(\.count).max() ?? 0,
            maxPlacesInOneMonth: placesByMonth.values.max() ?? 0,
            weekendCount: weekend,
            hasNewYear: newYear,
            hasChristmas: christmas
        )
    }

    static func unlockedIDs(places: [Place], members: [Member],
                            visitedPrefs: Set<String>, countryCount: Int = 0) -> [String] {
        let s = stats(places: places, members: members,
                      visitedPrefs: visitedPrefs, countryCount: countryCount)
        return all.filter { $0.isUnlocked(s) }.map(\.id)
    }
}
