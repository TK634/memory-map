import SwiftUI
import MapKit

/// 画面共通の見た目(カード・見出し・ボタンなど)。
/// やわらかいクリーム地に白いカードを浮かべる、SNS寄りのデザイン。
enum AppStyle {
    /// 画面の背景(上がクリーム、下に向かって白)
    static var background: some View {
        LinearGradient(colors: [Color(hex: "FFF3E3"), Color(hex: "FFFAF4")],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    /// 主ボタンのグラデーション
    static let accentGradient = LinearGradient(
        colors: [Color(hex: "F4A64C"), Color(hex: "E8863E")],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// 白い角丸カード
struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color(hex: "C98A4B").opacity(0.10), radius: 12, y: 4)
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardStyle(padding: padding)) }
}

/// カード上部の小見出し(絵文字+ラベル)
struct CardTitle: View {
    let emoji: String
    let title: LocalizedStringKey
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 6) {
            Text(emoji).font(.system(size: 15))
            Text(title)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(AppPalette.chrome)
            Spacer()
            if let trailing { trailing }
        }
    }
}

/// グラデーションの大きな主ボタン
struct PrimaryButtonStyle: ButtonStyle {
    var enabled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Capsule().fill(enabled ? AnyShapeStyle(AppStyle.accentGradient)
                                       : AnyShapeStyle(Color.gray.opacity(0.35)))
            )
            .shadow(color: AppPalette.accent.opacity(enabled ? 0.35 : 0), radius: 10, y: 5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// 押すと少し縮む(カードやチップ用)
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// メンバーの丸アイコン(頭文字)
struct MemberAvatar: View {
    let name: String
    let color: Color
    var size: CGFloat = 34

    var body: some View {
        Text(String(name.prefix(1)))
            .font(.system(size: size * 0.44, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: Circle())
    }
}

/// 場所のカテゴリに合うアイコンと色
enum PlaceCategoryIcon {
    static func symbol(for item: MKMapItem) -> (name: String, color: Color) {
        guard let c = item.pointOfInterestCategory else {
            return ("mappin", AppPalette.accent)
        }
        switch c {
        case .restaurant, .foodMarket: return ("fork.knife", Color(hex: "E86A5B"))
        case .cafe, .bakery: return ("cup.and.saucer.fill", Color(hex: "B9855A"))
        case .brewery, .winery, .nightlife: return ("wineglass.fill", Color(hex: "9B6ADB"))
        case .park, .nationalPark, .campground: return ("leaf.fill", Color(hex: "4FA36B"))
        case .beach: return ("beach.umbrella.fill", Color(hex: "3AA6C9"))
        case .museum, .library: return ("building.columns.fill", Color(hex: "7A6ADB"))
        case .amusementPark, .zoo, .aquarium: return ("sparkles", Color(hex: "E8963E"))
        case .hotel: return ("bed.double.fill", Color(hex: "5A8FD8"))
        case .airport: return ("airplane", Color(hex: "3A7CA5"))
        case .publicTransport: return ("tram.fill", Color(hex: "3A7CA5"))
        case .store: return ("bag.fill", Color(hex: "D64580"))
        case .stadium, .fitnessCenter: return ("figure.run", Color(hex: "E8963E"))
        case .theater, .movieTheater: return ("theatermasks.fill", Color(hex: "9B6ADB"))
        default: return ("mappin", AppPalette.accent)
        }
    }
}

/// 横に並べて、はみ出したら次の行へ折り返すレイアウト(チップ用)
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX; rowHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
