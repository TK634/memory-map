import SwiftUI
import AVKit
import AVFoundation
import CoreTransferable
import UniformTypeIdentifiers

/// 動画(プレミアム)。
/// iCloudの容量と同期の速さを守るため、720pに圧縮し最初の60秒だけ残す。
enum VideoPolicy {
    /// 残す長さの上限(秒)
    static let maxSeconds: Double = 60
}

/// 写真ライブラリから選んだ動画を一時ファイルとして受け取る
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedMovie(url: dest)
        }
    }
}

enum VideoProcessor {
    /// 動画を圧縮し、表紙画像(JPEG)と一緒に返す
    static func process(_ source: URL) async -> (video: Data, poster: Data)? {
        defer { try? FileManager.default.removeItem(at: source) }
        let asset = AVURLAsset(url: source)
        guard let duration = try? await asset.load(.duration) else { return nil }

        // 表紙: 0.5秒あたりの1コマ
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 1200, height: 1200)
        let at = CMTime(seconds: min(0.5, duration.seconds / 2), preferredTimescale: 600)
        guard let (cg, _) = try? await gen.image(at: at),
              let poster = UIImage(cgImage: cg).compressedJPEGData(maxEdge: 1200, quality: 0.75)
        else { return nil }

        // 本体: 720p・最初の60秒
        guard let session = AVAssetExportSession(asset: asset,
                                                 presetName: AVAssetExportPreset1280x720) else { return nil }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        defer { try? FileManager.default.removeItem(at: out) }
        let end = CMTime(seconds: min(duration.seconds, VideoPolicy.maxSeconds), preferredTimescale: 600)
        session.timeRange = CMTimeRange(start: .zero, end: end)
        session.shouldOptimizeForNetworkUse = true
        do {
            try await session.export(to: out, as: .mp4)
        } catch {
            return nil
        }
        guard let data = try? Data(contentsOf: out) else { return nil }
        return (data, poster)
    }
}

/// 動画の全画面再生
struct VideoPlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    let data: Data
    @State private var player: AVPlayer?
    @State private var fileURL: URL?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player).ignoresSafeArea()
            } else {
                ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .padding(16)
        }
        .task {
            // Data のままでは再生できないので一時ファイルに書き出す
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
            try? data.write(to: url)
            fileURL = url
            let p = AVPlayer(url: url)
            player = p
            p.play()
        }
        .onDisappear {
            player?.pause()
            if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        }
    }
}

/// 動画の表紙に重ねる再生マーク
struct PlayBadge: View {
    var size: CGFloat = 34
    var body: some View {
        Image(systemName: "play.fill")
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(.black.opacity(0.45), in: Circle())
    }
}
