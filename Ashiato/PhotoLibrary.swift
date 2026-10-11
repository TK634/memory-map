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

/// 写真を、行った場所ごとのアルバムにまとめて見返す画面
struct AlbumView: View {
    @Environment(\.dismiss) private var dismiss
    let places: [Place]
    let members: [Member]
    /// 写真の場所を開く
    var onOpenPlace: (Place) -> Void

    struct Item: Identifiable {
        let att: Attachment
        let place: Place
        var id: NSManagedObjectID { att.objectID }
    }
    struct AlbumViewerTarget: Identifiable {
        let index: Int
        var id: Int { index }
    }

    /// アルバムの単位。旅に入っている場所は旅の1冊にまとめる
    enum Entry: Identifiable {
        case trip(Trip)
        case place(Place)
        var id: NSManagedObjectID {
            switch self { case .trip(let t): t.objectID; case .place(let p): p.objectID }
        }
        var date: Date {
            switch self {
            case .trip(let t): t.startDate ?? t.createdAt ?? .distantPast
            case .place(let p): p.visitDate ?? p.createdAt ?? .distantPast
            }
        }
    }

    /// 写真のある旅・場所(行った日の新しい順)
    private var albums: [Entry] {
        let withPhotos = places.filter { !$0.photoAttachments.isEmpty }
        var seen = Set<NSManagedObjectID>()
        let trips = withPhotos.compactMap(\.trip).filter { !$0.isDeleted && seen.insert($0.objectID).inserted }
        let loose = withPhotos.filter { $0.trip == nil || $0.trip?.isDeleted == true }
        return (trips.map(Entry.trip) + loose.map(Entry.place)).sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppStyle.background
                let list = albums
                if list.isEmpty {
                    VStack(spacing: 12) {
                        Text("📸").font(.system(size: 48))
                        Text("まだ写真がありません")
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppPalette.chrome)
                        Text("記録画面から写真を追加すると、旅や行った場所ごとのアルバムになります。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                                  spacing: 14) {
                            ForEach(list) { entry in
                                switch entry {
                                case .trip(let t):
                                    NavigationLink {
                                        TripAlbumView(trip: t, openPlace: openPlace)
                                    } label: {
                                        TripAlbumCard(trip: t)
                                    }
                                    .buttonStyle(PressableStyle())
                                case .place(let p):
                                    NavigationLink {
                                        PlaceAlbumView(place: p, openPlace: openPlace)
                                    } label: {
                                        AlbumCard(place: p)
                                    }
                                    .buttonStyle(PressableStyle())
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationTitle("アルバム")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
        }
    }

    /// アルバムを閉じてから、その場所の記録画面を開く
    private func openPlace(_ p: Place) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onOpenPlace(p) }
    }
}

/// アルバム一覧の1枚(表紙・場所名・日付・枚数)
private struct AlbumCard: View {
    let place: Place

    var body: some View {
        let photos = place.photoAttachments
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let cover = photos.first { PhotoThumb(attachment: cover, pixel: 400) }
                }
                .clipped()
                .overlay(alignment: .topTrailing) {
                    Label("\(photos.count)", systemImage: "photo.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(7)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(place.name ?? "")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppPalette.chrome)
                    .lineLimit(1)
                if let d = place.visitDate {
                    Text(d.jaDateText)
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

/// 旅のアルバムの表紙(旅の名前・期間・枚数)
private struct TripAlbumCard: View {
    @ObservedObject var trip: Trip

    var body: some View {
        let count = trip.placeList.reduce(0) { $0 + $1.photoAttachments.count }
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let cover = trip.coverPhoto { PhotoThumb(attachment: cover, pixel: 400) }
                }
                .clipped()
                .overlay(alignment: .topLeading) {
                    Label("旅", systemImage: "suitcase.fill")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(AppPalette.accent, in: Capsule())
                        .padding(7)
                }
                .overlay(alignment: .topTrailing) {
                    Label("\(count)", systemImage: "photo.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(7)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(trip.displayName)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppPalette.chrome)
                    .lineLimit(1)
                Text("\(trip.periodText) · \(trip.placeList.count)か所")
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
    }
}

/// 旅のアルバム。旅の順番どおり、日ごと・場所ごとに写真を並べる
struct TripAlbumView: View {
    @ObservedObject var trip: Trip
    /// 場所の記録を開く(旅の画面から開いたときは nil = 写真を見るだけ)
    var openPlace: ((Place) -> Void)? = nil
    @State private var viewer: AlbumView.AlbumViewerTarget?

    /// 旅の順(場所の行った順 → 場所の中は古い順)の全写真
    private var items: [AlbumView.Item] {
        trip.orderedPlaces.flatMap { p in
            p.photoAttachments.reversed().map { AlbumView.Item(att: $0, place: p) }
        }
    }

    var body: some View {
        let list = items
        let days = trip.days
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 6) {
                    Label(trip.periodText, systemImage: "calendar")
                    Spacer()
                    Text("\(list.count)枚")
                }
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 4)

                ForEach(Array(days.enumerated()), id: \.element) { i, day in
                    let placesWithPhotos = trip.places(on: day).filter { !$0.photoAttachments.isEmpty }
                    if !placesWithPhotos.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(i + 1)日目  \(day.formatted(.dateTime.month().day().weekday(.abbreviated).locale(AppRegion.preferredLocale)))")
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundStyle(AppPalette.chrome)
                            ForEach(placesWithPhotos, id: \.objectID) { p in
                                VStack(alignment: .leading, spacing: 6) {
                                    Button { openPlace?(p) } label: {
                                        HStack(spacing: 6) {
                                            RouteNumberBadge(number: (trip.orderedPlaces.firstIndex(of: p) ?? 0) + 1, size: 20)
                                            Text(p.name ?? "").font(.subheadline.bold())
                                                .foregroundStyle(AppPalette.chrome)
                                            if openPlace != nil {
                                                Image(systemName: "chevron.right")
                                                    .font(.caption2.bold()).foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(openPlace == nil)
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                                        ForEach(p.photoAttachments.reversed(), id: \.objectID) { att in
                                            Button {
                                                if let idx = list.firstIndex(where: { $0.att.objectID == att.objectID }) {
                                                    viewer = AlbumView.AlbumViewerTarget(index: idx)
                                                }
                                            } label: {
                                                Color.clear
                                                    .aspectRatio(1, contentMode: .fit)
                                                    .overlay(PhotoThumb(attachment: att, pixel: 300))
                                                    .clipped()
                                                    .overlay { if att.isVideo { PlayBadge(size: 28) } }
                                            }
                                            .buttonStyle(PressableStyle())
                                        }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }
                    }
                }
                if list.isEmpty {
                    Text("この旅にはまだ写真がありません。行った場所の記録から写真を追加すると、ここにまとまります。")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.top, 20)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(AppStyle.background)
        .navigationTitle(trip.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $viewer) { t in
            AlbumPhotoViewer(items: list, index: t.index) { p in
                viewer = nil
                openPlace?(p)
            }
        }
    }
}

/// 1か所のアルバム(その場所の写真を一覧で)
private struct PlaceAlbumView: View {
    @ObservedObject var place: Place
    var openPlace: (Place) -> Void
    @State private var viewer: AlbumView.AlbumViewerTarget?

    /// 古い順(旅の流れで見返せるように)
    private var items: [AlbumView.Item] {
        place.photoAttachments.reversed().map { AlbumView.Item(att: $0, place: place) }
    }

    var body: some View {
        let list = items
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    if let d = place.visitDate {
                        Label(d.jaDateText, systemImage: "calendar")
                    }
                    if let t = place.trip {
                        Label(t.displayName, systemImage: "suitcase.fill")
                    }
                    Spacer()
                    Text("\(list.count)枚")
                }
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 4)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, item in
                        Button { viewer = AlbumView.AlbumViewerTarget(index: i) } label: {
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(PhotoThumb(attachment: item.att, pixel: 300))
                                .clipped()
                                .overlay { if item.att.isVideo { PlayBadge(size: 28) } }
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(AppStyle.background)
        .navigationTitle(place.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("記録を開く") { openPlace(place) }
            }
        }
        .fullScreenCover(item: $viewer) { t in
            AlbumPhotoViewer(items: list, index: t.index) { p in
                viewer = nil
                openPlace(p)
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
