import SwiftUI
import Combine
import CoreLocation

/// 実績の解放・制県レベルアップを検知して祝う仕組み。
/// 「記録する→すぐ報われる」ループを閉じるのが目的。
enum CelebrationKind: Equatable {
    case badge(id: String, icon: String, detail: String)
    case prefecture(name: String, count: Int)
    case milestone(title: String, detail: String, icon: String)
}

@MainActor
final class CelebrationCenter: ObservableObject {
    static let shared = CelebrationCenter()
    @Published var pending: [CelebrationKind] = []

    private init() {}

    /// 記録の保存前後で比較して、新しく解放されたものを積む
    func check(places: [Place], members: [Member], prefRegions: [GeoRegion]) {
        let snapshot = Snapshot(places: places, members: members, prefRegions: prefRegions)
        defer { last = snapshot }
        guard let before = last else { return }   // 初回は基準を取るだけ

        // 新しく塗られた県
        let newPrefs = snapshot.prefs.subtracting(before.prefs)
        for name in newPrefs.sorted() {
            pending.append(.prefecture(name: name, count: snapshot.prefs.count))
        }
        // 新しく解放されたバッジ
        let newBadges = snapshot.badges.subtracting(before.badges)
        for id in newBadges.sorted() {
            if let b = BadgeCatalog.all.first(where: { $0.id == id }) {
                pending.append(.badge(id: b.id, icon: b.icon, detail: b.condition))
            }
        }
        // 記録数の節目
        for n in [10, 30, 50, 100] where before.placeCount < n && snapshot.placeCount >= n {
            pending.append(.milestone(title: "\(n)か所目のあしあと",
                                      detail: "コツコツ続けていますね。",
                                      icon: "shoeprints.fill"))
        }
    }

    private var last: Snapshot?

    private struct Snapshot {
        let prefs: Set<String>
        let badges: Set<String>
        let placeCount: Int

        init(places: [Place], members: [Member], prefRegions: [GeoRegion]) {
            let jp = places.filter(\.isJapan).map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
            prefs = GeoRegion.visitedNames(of: prefRegions, coords: jp)
            placeCount = places.count
            badges = Set(BadgeCatalog.unlockedIDs(places: places, members: members,
                                                  visitedPrefs: prefs))
        }
    }
}

// MARK: - 祝福の全画面演出

struct CelebrationOverlay: View {
    let kind: CelebrationKind
    let onClose: () -> Void

    @State private var appeared = false

    private var title: String {
        switch kind {
        case .badge: return "バッジ獲得!"
        case .prefecture(let name, _): return "\(name) 制覇!"
        case .milestone(let t, _, _): return t
        }
    }
    private var subtitle: String {
        switch kind {
        case .badge(let id, _, let detail): return "「\(id)」\n\(detail)"
        case .prefecture(_, let count): return "制県レベル \(count) / 47"
        case .milestone(_, let d, _): return d
        }
    }
    private var icon: String {
        switch kind {
        case .badge(_, let icon, _): return icon
        case .prefecture: return "map.fill"
        case .milestone(_, _, let icon): return icon
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture { onClose() }

            ConfettiView()
                .allowsHitTesting(false)

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color(hex: "FFD9A8"), AppPalette.accent],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 116, height: 116)
                        .shadow(color: AppPalette.accent.opacity(0.5), radius: 18, y: 6)
                    Image(systemName: icon)
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(.white)
                }
                .scaleEffect(appeared ? 1 : 0.4)
                .rotationEffect(.degrees(appeared ? 0 : -25))

                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(AppPalette.chrome)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button(action: onClose) {
                    Text("やった!")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(AppPalette.accent, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .padding(.top, 4)
            }
            .padding(28)
            .frame(maxWidth: 320)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26))
            .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { appeared = true }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

/// 紙吹雪
struct ConfettiView: View {
    private struct Piece: Identifiable {
        let id = UUID()
        let x: CGFloat
        let delay: Double
        let color: Color
        let size: CGFloat
        let spin: Double
    }

    private let pieces: [Piece] = (0..<70).map { _ in
        Piece(x: .random(in: 0...1),
              delay: .random(in: 0...0.5),
              color: [Color(hex: "E8963E"), Color(hex: "FFC2B4"), Color(hex: "AFE6D6"),
                      Color(hex: "B0D8F2"), Color(hex: "FFF2B0"), Color(hex: "CFC0F0")]
                .randomElement()!,
              size: .random(in: 6...12),
              spin: .random(in: -720...720))
    }

    @State private var falling = false

    var body: some View {
        GeometryReader { geo in
            ForEach(pieces) { p in
                RoundedRectangle(cornerRadius: 2)
                    .fill(p.color)
                    .frame(width: p.size, height: p.size * 1.6)
                    .position(x: p.x * geo.size.width,
                              y: falling ? geo.size.height + 60 : -60)
                    .rotationEffect(.degrees(falling ? p.spin : 0))
                    .opacity(falling ? 0.2 : 1)
                    .animation(.easeIn(duration: Double.random(in: 1.8...3.0)).delay(p.delay),
                               value: falling)
            }
        }
        .onAppear { falling = true }
    }
}
