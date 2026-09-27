import Foundation
import CoreData
import UIKit
import AVFoundation

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
        if existing >= 5 {
            // すでにデータがあるときは、小さな国の検証データだけ追加できる
            if ProcessInfo.processInfo.arguments.contains("-seedSmallCountries") {
                let r2 = NSFetchRequest<Place>(entityName: "Place")
                r2.predicate = NSPredicate(format: "name == %@", "マリーナベイ")
                if ((try? context.count(for: r2)) ?? 0) == 0 {
                    let members = (try? context.fetch(NSFetchRequest<Member>(entityName: "Member"))) ?? []
                    for (name, lat, lon) in [("マリーナベイ", 1.2834, 103.8607), ("タモン湾", 13.5162, 144.8032)] {
                        let p = Place(context: context)
                        p.id = UUID(); p.createdAt = Date(); p.log = log
                        p.name = name; p.latitude = lat; p.longitude = lon; p.isJapan = false
                        p.year = 2025
                        p.visitDate = Calendar.current.date(from: DateComponents(year: 2025, month: 11, day: 3))
                        p.visitorIDList = members.compactMap(\.id)
                    }
                    try? context.save()
                }
            }
            return
        }

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
        /// 見た目確認用の写真(グラデーション+絵文字)
        func samplePhoto(_ emoji: String, _ c1: UIColor, _ c2: UIColor) -> Data? {
            let size = CGSize(width: 600, height: 600)
            let img = UIGraphicsImageRenderer(size: size).image { ctx in
                let colors = [c1.cgColor, c2.cgColor] as CFArray
                let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil)!
                ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 600, y: 600), options: [])
                let text = emoji as NSString
                text.draw(at: CGPoint(x: 170, y: 150),
                          withAttributes: [.font: UIFont.systemFont(ofSize: 260)])
            }
            return img.jpegData(compressionQuality: 0.8)
        }

        // 写真10枚(→「おもいでカメラ」)。2x2の小さなJPEG
        let img = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { ctx in
            UIColor.orange.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let okinawa: [(String, UIColor, UIColor)] = [
            ("🏝️", .systemTeal, .systemBlue), ("🐠", .cyan, .systemIndigo), ("🌺", .systemPink, .systemOrange),
            ("🍍", .systemYellow, .systemGreen), ("🌅", .systemOrange, .systemPurple),
        ]
        _ = img
        for i in 1...10 {
            let spec = okinawa[(i - 1) % okinawa.count]
            if let jpeg = samplePhoto(spec.0, spec.1, spec.2) {
                let a = Attachment(context: context)
                a.id = UUID(); a.createdAt = Date().addingTimeInterval(Double(100 + i))
                a.imageData = jpeg
                a.authorName = i % 2 == 0 ? "タカ" : "ハナ"
                a.place = naha
            }
        }

        // 「1年前の今日」カードの確認用: 1年前・2年前の同月日の記録を追加
        if ProcessInfo.processInfo.arguments.contains("-seedMemories") {
            let cal = Calendar.current
            for (yearsAgo, place) in [(1, "鎌倉"), (2, "箱根")] {
                let d = cal.date(byAdding: .year, value: -yearsAgo, to: Date())!
                let p = Place(context: context)
                p.id = UUID(); p.createdAt = Date(); p.log = log
                p.name = place
                p.latitude = place == "鎌倉" ? 35.319 : 35.232
                p.longitude = place == "鎌倉" ? 139.546 : 139.106
                p.isJapan = true
                p.year = Int16(cal.component(.year, from: d))
                p.visitDate = d
                p.visitorIDList = both
            }
        }

        // カレンダーの塗り分け確認用: 3人目を加え、1人/2人/3人の日を今月に混ぜる
        if ProcessInfo.processInfo.arguments.contains("-seedCalendarMix") {
            let m3 = makeMember("ソラ", "5B9A6B")
            let cal = Calendar.current
            let now = Date()
            func day(_ d: Int) -> Date {
                var c = cal.dateComponents([.year, .month], from: now); c.day = d
                return cal.date(from: c)!
            }
            let mix: [(String, Int, Int?, [UUID])] = [
                ("代官山のカフェ", 3, nil, [m1.id!]),
                ("鎌倉",         7, nil, [m2.id!]),
                ("箱根",        12, 13,  [m1.id!, m2.id!]),
                ("江の島",      20, nil, [m1.id!, m2.id!, m3.id!]),
                ("高尾山",      21, nil, [m1.id!, m3.id!]),
            ]
            for (name, d, e, who) in mix {
                let p = Place(context: context)
                p.id = UUID(); p.createdAt = Date(); p.log = log
                p.name = name; p.latitude = 35.3; p.longitude = 139.5; p.isJapan = true
                p.year = Int16(cal.component(.year, from: now))
                p.visitDate = day(d); p.visitEndDate = e.map(day)
                p.visitorIDList = who
                let photo: (String, UIColor, UIColor)? = [
                    "代官山のカフェ": ("☕️", UIColor.brown, UIColor.systemOrange),
                    "箱根": ("♨️", UIColor.systemRed, UIColor.systemPink),
                    "江の島": ("🌊", UIColor.systemBlue, UIColor.systemTeal),
                ][name]
                if let photo, let jpeg = samplePhoto(photo.0, photo.1, photo.2) {
                    let a = Attachment(context: context)
                    a.id = UUID(); a.createdAt = Date(); a.imageData = jpeg
                    a.authorName = "タカ"; a.place = p
                }
            }
        }

        // 小さな国の判定確認用: シンガポール・グアム(国コードは空のまま入れ、後から補う処理を確かめる)
        if ProcessInfo.processInfo.arguments.contains("-seedSmallCountries") {
            for (name, lat, lon) in [("マリーナベイ", 1.2834, 103.8607), ("タモン湾", 13.5162, 144.8032)] {
                let p = Place(context: context)
                p.id = UUID(); p.createdAt = Date(); p.log = log
                p.name = name; p.latitude = lat; p.longitude = lon; p.isJapan = false
                p.year = 2025; p.visitDate = date(2025, 11, 3); p.visitorIDList = both
            }
        }

        // 見た目確認用のリアクション(スクショ・デザイン検証)
        if ProcessInfo.processInfo.arguments.contains("-seedReactions") {
            for (emoji, who) in [("❤️", "タカ"), ("❤️", "ハナ"), ("🎉", "ハナ"), ("📸", "タカ")] {
                let r = Reaction(context: context)
                r.id = UUID(); r.emoji = emoji; r.createdAt = Date(); r.authorName = who
                r.place = tokyo
            }
        }

        try? context.save()
        print("[DemoSeeder] サンプルデータ投入完了")

        if ProcessInfo.processInfo.arguments.contains("-verifyReactions") {
            verifyReactions(context: context, place: tokyo, me: "タカ", other: "ハナ")
        }
    }

    /// 動画の取り込み(圧縮・表紙作成)を検証し、東京の記録に付ける(DEBUGのみ)
    static func verifyVideo(context: NSManagedObjectContext) async {
        let src = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID()).mov")
        guard makeTestMovie(at: src) else { print("[動画検証] テスト動画の作成に失敗"); return }
        let srcSize = (try? Data(contentsOf: src).count) ?? 0
        guard let result = await VideoProcessor.process(src) else { print("[動画検証] 圧縮に失敗"); return }
        print("[動画検証] 元: \(srcSize)バイト → 圧縮後: \(result.video.count)バイト, 表紙: \(result.poster.count)バイト")
        let req = NSFetchRequest<Place>(entityName: "Place")
        req.predicate = NSPredicate(format: "name == %@", "東京")
        if let tokyo = (try? context.fetch(req))?.first {
            let a = Attachment(context: context)
            a.id = UUID(); a.createdAt = Date(); a.authorName = "タカ"
            a.imageData = result.poster; a.videoData = result.video; a.isVideo = true
            a.place = tokyo
            try? context.save()
            print("[動画検証] 東京に動画を保存: isVideo=\(a.isVideo)")
        }
    }

    /// 2秒のテスト動画(色が変わる)を作る
    private static func makeTestMovie(at url: URL) -> Bool {
        let size = CGSize(width: 640, height: 480)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return false }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: size.width, kCVPixelBufferHeightKey as String: size.height,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        let colors: [UIColor] = [.systemOrange, .systemBlue, .systemGreen, .systemPink]
        for frame in 0..<30 {
            while !input.isReadyForMoreMediaData { usleep(1000) }
            var pb: CVPixelBuffer?
            CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB, nil, &pb)
            guard let buffer = pb else { return false }
            CVPixelBufferLockBaseAddress(buffer, [])
            let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width),
                                height: Int(size.height), bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
            ctx?.setFillColor(colors[(frame / 8) % colors.count].cgColor)
            ctx?.fill(CGRect(origin: .zero, size: size))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 15))
        }
        input.markAsFinished()
        let sem = DispatchSemaphore(value: 0)
        writer.finishWriting { sem.signal() }
        sem.wait()
        return writer.status == .completed
    }

    /// リアクションの追加・重複トグル・集計を検証(DEBUGのみ)
    private static func verifyReactions(context: NSManagedObjectContext,
                                        place: Place?, me: String, other: String) {
        guard let place else { return }
        func add(_ emoji: String, by author: String) {
            let r = Reaction(context: context)
            r.id = UUID(); r.emoji = emoji; r.createdAt = Date(); r.authorName = author
            r.place = place
        }
        func all() -> [Reaction] { Array((place.reactions as? Set<Reaction>) ?? []) }

        add("❤️", by: me)
        add("❤️", by: other)
        add("🎉", by: other)
        try? context.save()
        print("[検証] 追加後の総数: \(all().count) (期待: 3)")

        var counts: [String: Int] = [:]
        for r in all() { counts[r.emoji ?? "", default: 0] += 1 }
        print("[検証] 集計: \(counts.sorted { $0.key < $1.key }) (期待: ❤️=2, 🎉=1)")

        let mine = all().filter { $0.authorName == me }
        print("[検証] 自分のリアクション: \(mine.count) (期待: 1)")

        // トグル(取り消し)
        if let target = all().first(where: { $0.emoji == "❤️" && $0.authorName == me }) {
            context.delete(target)
            try? context.save()
        }
        print("[検証] 取り消し後の総数: \(all().count) (期待: 2)")
        let heartLeft = all().filter { $0.emoji == "❤️" }
        print("[検証] 残った❤️の作者: \(heartLeft.compactMap(\.authorName)) (期待: [ハナ])")

        // 後片付け(検証データを消す)
        all().forEach(context.delete)
        try? context.save()
        print("[検証] 後片付け完了。総数: \(all().count) (期待: 0)")
    }
}
#endif
