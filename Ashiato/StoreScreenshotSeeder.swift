import Foundation
import CoreData
import UIKit

#if DEBUG
/// App Store のスクリーンショット撮影用データ(DEBUG専用・配信版には含まれない)。
/// 起動引数 -seedStore で投入する。写真はアプリの Documents/StorePhotos/ に置いた JPEG を使う。
/// 例: xcrun simctl launch <SIM> com.tk634.Ashiato -seedStore -hasSeenOnboarding YES
enum StoreScreenshotSeeder {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-seedStore")
    }

    static func seedIfRequested(context: NSManagedObjectContext, log: TravelLog) {
        guard isRequested else { return }
        // 二重投入しない
        if ((try? context.count(for: NSFetchRequest<Place>(entityName: "Place"))) ?? 0) > 0 { return }

        func member(_ name: String, _ hex: String) -> Member {
            let m = Member(context: context)
            m.id = UUID(); m.name = name; m.colorHex = hex; m.createdAt = Date(); m.log = log
            return m
        }
        let taka = member("タカ", "E8963E").id!
        // 撮影時に「あなたはどの人?」が出ないよう、このiPhoneの「自分」をタカにする
        UserDefaults.standard.set(taka.uuidString, forKey: "myMemberID")
        let hana = member("ハナ", "5A8FD8").id!
        let both = [taka, hana]

        func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
            Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
        }
        let photoDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StorePhotos")
        func photo(_ file: String) -> Data? {
            guard let img = UIImage(contentsOfFile: photoDir.appendingPathComponent(file).path) else { return nil }
            return img.jpegData(compressionQuality: 0.85)   // 向き(EXIF)を反映した状態で保存
        }

        // (名前, 緯度, 経度, 国内, 訪問日, 帰着日, 訪問者, 写真, コメント)
        let rows: [(String, Double, Double, Bool, Date, Date?, [UUID], [String], [String])] = [
            ("扇沢駅", 36.5867, 137.7186, true, day(2026, 10, 3), nil, both, ["01_ogisawa.jpg"],
             ["ここからアルペンルート!"]),
            ("立山・雄山", 36.5753, 137.6197, true, day(2026, 10, 3), day(2026, 10, 4), both,
             ["03_cloudsea.jpg", "04_summit_panorama.jpg", "02_trail.jpg", "06_dinner.jpg", "07_foggy_window.jpg"],
             ["山頂から見た雲海、一生忘れない", "ホテルの夕ごはんが豪華だった"]),
            ("みくりが池", 36.5847, 137.6016, true, day(2026, 10, 4), nil, both,
             ["09_mikurigaike_wide.jpg", "08_mikurigaike_sign.jpg"], ["池が鏡みたいだった"]),
            ("信濃大町のおそば屋さん", 36.5030, 137.8510, true, day(2026, 10, 4), nil, both,
             ["10_soba.jpg"], ["下山後のおろしそば、最高"]),
            ("上高地・大正池", 36.2187, 137.6366, true, day(2026, 10, 5), nil, both,
             ["11_taishoike.jpg", "12_azusagawa.jpg"], []),
            ("箱根", 35.2324, 139.1069, true, day(2026, 9, 21), day(2026, 9, 22), both, [], ["温泉でのんびり"]),
            ("江の島", 35.2993, 139.4800, true, day(2026, 9, 12), nil, [hana], [], []),
            ("代官山のカフェ", 35.6489, 139.7030, true, day(2026, 9, 27), nil, both, [], []),
            ("金沢", 36.5613, 136.6562, true, day(2026, 5, 3), day(2026, 5, 4), both, [], []),
            ("那覇", 26.2124, 127.6809, true, day(2026, 6, 14), day(2026, 6, 17), both, [], []),
            ("京都", 35.0116, 135.7681, true, day(2026, 3, 29), nil, both, [], []),
            ("札幌", 43.0618, 141.3545, true, day(2025, 12, 28), nil, both, [], []),
            ("大阪", 34.6937, 135.5023, true, day(2025, 7, 20), nil, [taka], [], []),
            ("福岡", 33.5904, 130.4017, true, day(2025, 9, 15), nil, [hana], [], []),
            ("台北", 25.0330, 121.5654, false, day(2025, 12, 30), nil, both, [], []),
            ("パリ", 48.8566, 2.3522, false, day(2026, 1, 2), day(2026, 1, 6), both, [], []),
        ]

        var order = 0.0
        for (n, r) in rows.enumerated() {
            let p = Place(context: context)
            // 同じ日の中の順番が保てるよう、登録時刻を少しずつずらす
            p.id = UUID(); p.createdAt = r.4.addingTimeInterval(Double(n)); p.log = log
            p.name = r.0; p.latitude = r.1; p.longitude = r.2; p.isJapan = r.3
            p.year = Int16(Calendar.current.component(.year, from: r.4))
            p.visitDate = r.4; p.visitEndDate = r.5
            p.visitorIDList = r.6
            for (i, file) in r.7.enumerated() {
                guard let jpeg = photo(file) else { continue }
                let a = Attachment(context: context)
                order += 1
                a.id = UUID(); a.createdAt = r.4.addingTimeInterval(order)
                a.imageData = jpeg
                a.authorName = i % 2 == 0 ? "タカ" : "ハナ"
                a.place = p
            }
            for (i, text) in r.8.enumerated() {
                let a = Attachment(context: context)
                order += 1
                a.id = UUID(); a.createdAt = r.4.addingTimeInterval(order)
                a.comment = text
                a.authorName = i % 2 == 0 ? "ハナ" : "タカ"
                a.place = p
            }
        }
        try? context.save()
        // 期間内の5か所を、行った順の旅にまとめる
        Trip.make(in: context, log: log, start: day(2026, 10, 3), end: day(2026, 10, 5),
                  name: "立山・上高地の旅", memberIDs: both)
    }
}
#endif
