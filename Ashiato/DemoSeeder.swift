import Foundation
import CoreData
import UIKit

#if DEBUG
/// 起動引数 -seedDemo でサンプルデータを投入する(検証・スクリーンショット用)
/// 例: xcrun simctl launch <SIM> com.tk634.Ashiato -seedDemo -showAchievements
enum DemoSeeder {

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-seedDemo")
    }
    static var shouldShowAchievements: Bool {
        ProcessInfo.processInfo.arguments.contains("-showAchievements")
    }

    static func seedIfRequested(context: NSManagedObjectContext, log: TravelLog) {
        guard isRequested else { return }
        let req = NSFetchRequest<Place>(entityName: "Place")
        let existing = (try? context.count(for: req)) ?? 0
        guard existing < 5 else { return }   // 二重投入防止

        // メンバー2人
        func makeMember(_ name: String, _ hex: String) -> Member {
            let m = Member(context: context)
            m.id = UUID(); m.name = name; m.colorHex = hex; m.createdAt = Date(); m.log = log
            return m
        }
        let m1 = makeMember("タカ", "E8963E")
        let m2 = makeMember("ハナ", "5A8FD8")
        let both = [m1.id!, m2.id!]

        func date(_ y: Int, _ mo: Int, _ d: Int) -> Date {
            Calendar.current.date(from: DateComponents(year: y, month: mo, day: d))!
        }

        // (名前, 緯度, 経度, 国内, 年, 訪問日, 帰着日, 訪問者)
        let rows: [(String, Double, Double, Bool, Int, Date?, Date?, [UUID])] = [
            ("東京",     35.68, 139.76, true,  2024, date(2024, 4, 10), nil,               both),
            ("大阪",     34.69, 135.50, true,  2024, date(2024, 7, 20), nil,               both),
            ("名古屋",   35.18, 136.90, true,  2025, date(2025, 10, 5), nil,               [m1.id!]),
            ("札幌",     43.06, 141.35, true,  2025, date(2025, 12, 28), nil,              both),
            ("那覇",     26.21, 127.68, true,  2026, date(2026, 6, 14), date(2026, 6, 17), both),
            ("京都",     35.01, 135.77, true,  2026, date(2026, 3, 30), nil,               both),
            ("福岡",     33.59, 130.40, true,  2025, date(2025, 9, 15), nil,               [m2.id!]),
            ("パリ",     48.85, 2.35,   false, 2026, date(2026, 1, 2),  nil,               both),
            ("ローマ",   41.90, 12.49,  false, 2026, date(2026, 1, 5),  nil,               [m1.id!]),
            ("バンコク", 13.75, 100.50, false, 2025, date(2025, 8, 12), nil,               both),
        ]

        var tokyo: Place?
        var naha: Place?
        for r in rows {
            let p = Place(context: context)
            p.id = UUID(); p.createdAt = Date(); p.log = log
            p.name = r.0; p.latitude = r.1; p.longitude = r.2
            p.isJapan = r.3; p.year = Int16(r.4)
            p.visitDate = r.5; p.visitEndDate = r.6
            p.visitorIDList = r.7
            if r.0 == "東京" { tokyo = p }
            if r.0 == "那覇" { naha = p }
        }

        // コメント10件(→「ことばのあしあと」)
        for i in 1...10 {
            let a = Attachment(context: context)
            a.id = UUID(); a.createdAt = Date().addingTimeInterval(Double(i))
            a.comment = "たのしかった思い出 その\(i)"
            a.place = tokyo
        }
        // 写真10枚(→「おもいでカメラ」)。2x2の小さなJPEG
        let img = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { ctx in
            UIColor.orange.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        if let jpeg = img.jpegData(compressionQuality: 0.7) {
            for i in 1...10 {
                let a = Attachment(context: context)
                a.id = UUID(); a.createdAt = Date().addingTimeInterval(Double(100 + i))
                a.imageData = jpeg
                a.place = naha
            }
        }

        try? context.save()
        print("[DemoSeeder] サンプルデータ投入完了")
    }
}
#endif
