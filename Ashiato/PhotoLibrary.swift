import SwiftUI
import UIKit
import ImageIO
import CoreData

// MARK: - 方針

enum PremiumPolicy {
    /// 無料で残せる写真の枚数(1か所あたり)。プレミアムは無制限
    static let freePhotosPerPlace = 3
}

// MARK: - サムネイル

/// 写真の縮小版を作って覚えておく(カレンダー・地図・アルバムで何度も使うため)
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, UIImage>()

    /// 長辺 pixel ピクセルの縮小画像。元の大きな画像はデコードしない(ImageIOで直接縮小)
    func thumbnail(for att: Attachment, pixel: CGFloat = 240) -> UIImage? {
        let key = "\(att.objectID.uriRepresentation().absoluteString)#\(Int(pixel))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let data = att.imageData,
              let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: pixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let img = UIImage(cgImage: cg)
        cache.setObject(img, forKey: key)
        return img
    }
}

extension Place {
    /// この場所の写真(新しい順)
    var photoAttachments: [Attachment] {
        ((attachments as? Set<Attachment>) ?? [])
            .filter { $0.imageData != nil }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    /// 表紙にする写真(いちばん新しいもの)
    var coverPhoto: Attachment? { photoAttachments.first }
}

/// 写真の縮小版を表示する(無ければ何も出さない)
struct PhotoThumb: View {
    let attachment: Attachment
    var pixel: CGFloat = 240

    var body: some View {
        if let img = ThumbnailCache.shared.thumbnail(for: attachment, pixel: pixel) {
            Image(uiImage: img).resizable().scaledToFill()
        } else {
            Color.gray.opacity(0.15)
        }
    }
}

// MARK: - アルバム

/// すべての写真を、行った月ごとに並べて見返す画面
struct AlbumView: View {
    @Environment(\.dismiss) private var dismiss
    let places: [Place]
    let members: [Member]
    /// 写真の場所を開く
    var onOpenPlace: (Place) -> Void

    @State private var viewer: AlbumViewerTarget?

    struct Item: Identifiable {
        let att: Attachment
        let place: Place
        var id: NSManagedObjectID { att.objectID }
    }
    struct AlbumViewerTarget: Identifiable {
        let index: Int
        var id: Int { index }
    }

    /// 写真を行った日の新しい順に並べる
    private var items: [Item] {
        places.flatMap { p in p.photoAttachments.map { Item(att: $0, place: p) } }
            .sorted { a, b in
                let da = a.place.visitDate ?? a.att.createdAt ?? .distantPast
                let db = b.place.visitDate ?? b.att.createdAt ?? .distantPast
                return da > db
            }
    }

    /// 月ごとの見出しでまとめる
    private var sections: [(title: String, items: [(Int, Item)])] {
        var result: [(String, [(Int, Item)])] = []
        for (i, item) in items.enumerated() {
            let d = item.place.visitDate ?? item.att.createdAt ?? Date()
            let title = d.formatted(.dateTime.year().month(.wide).locale(AppRegion.preferredLocale))
            if result.last?.0 == title {
                result[result.count - 1].1.append((i, item))
            } else {
                result.append((title, [(i, item)]))
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppStyle.background
                if items.isEmpty {
                    VStack(spacing: 12) {
                        Text("📸").font(.system(size: 48))
                        Text("まだ写真がありません")
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppPalette.chrome)
                        Text("記録画面から写真を追加すると、ここに集まります。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(sections, id: \.title) { sec in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(sec.title)
                                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                                        .foregroundStyle(AppPalette.chrome)
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3),
                                              spacing: 3) {
                                        ForEach(sec.items, id: \.1.id) { index, item in
                                            Button { viewer = AlbumViewerTarget(index: index) } label: {
                                                Color.clear
                                                    .aspectRatio(1, contentMode: .fit)
                                                    .overlay(PhotoThumb(attachment: item.att, pixel: 300))
                                                    .clipped()
                                                    .overlay { if item.att.isVideo { PlayBadge(size: 28) } }
                                                    .overlay(alignment: .bottomLeading) {
                                                        Text(item.place.name ?? "")
                                                            .font(.system(size: 10, weight: .bold))
                                                            .foregroundStyle(.white)
                                                            .lineLimit(1)
                                                            .padding(5)
                                                            .shadow(color: .black.opacity(0.6), radius: 2)
                                                    }
                                            }
                                            .buttonStyle(PressableStyle())
                                        }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationTitle("アルバム")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
            .fullScreenCover(item: $viewer) { t in
                AlbumPhotoViewer(items: items, index: t.index) { place in
                    viewer = nil
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onOpenPlace(place) }
                }
            }
        }
    }
}

/// アルバム用の全画面ビューア。写真はページを開いたときに読み込む(大量でも軽い)
struct AlbumPhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let items: [AlbumView.Item]
    @State var index: Int
    var onOpenPlace: (Place) -> Void
    @State private var playing: VideoPlayerItem?

    struct VideoPlayerItem: Identifiable {
        let id = UUID()
        let data: Data
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    Group {
                        if let img = ThumbnailCache.shared.thumbnail(for: item.att, pixel: 1600) {
                            Image(uiImage: img).resizable().scaledToFit()
                        } else {
                            ProgressView().tint(.white)
                        }
                    }
                    .overlay {
                        if item.att.isVideo {
                            Button {
                                if let v = item.att.videoData { playing = VideoPlayerItem(data: v) }
                            } label: { PlayBadge(size: 72) }
                        }
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .fullScreenCover(item: $playing) { v in VideoPlayerScreen(data: v.data) }

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                    Spacer()
                    Text("\(index + 1) / \(items.count)")
                        .font(.footnote.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.black.opacity(0.4), in: Capsule())
                }
                .padding(.horizontal, 16)
                Spacer()
                if index < items.count {
                    let item = items[index]
                    Button { onOpenPlace(item.place) } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.place.name ?? "")
                                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                                HStack(spacing: 6) {
                                    if let d = item.place.visitDate { Text(d.jaDateText) }
                                    if let who = item.att.authorName { Text("· \(who)") }
                                }
                                .font(.caption).opacity(0.85)
                            }
                            Spacer()
                            Text("この場所を開く")
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(.white.opacity(0.2), in: Capsule())
                        }
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }
        }
        .statusBarHidden()
    }
}
