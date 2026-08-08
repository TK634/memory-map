import SwiftUI
import CoreData

/// 場所へのリアクション(スタンプ)。共有相手の記録に反応でき、見るだけの人も参加できる
struct ReactionBar: View {
    @Environment(\.managedObjectContext) private var context
    let place: Place
    /// 自分の名前(メンバー名。未設定なら nil)
    let myName: String?

    static let choices = ["❤️", "👍", "😊", "🎉", "🍜", "📸"]

    private var reactions: [Reaction] {
        ((place.reactions as? Set<Reaction>) ?? [])
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    /// 絵文字ごとの件数
    private var counts: [(emoji: String, count: Int, mine: Bool)] {
        var dict: [String: (Int, Bool)] = [:]
        for r in reactions {
            guard let e = r.emoji else { continue }
            let cur = dict[e] ?? (0, false)
            dict[e] = (cur.0 + 1, cur.1 || (r.authorName != nil && r.authorName == myName))
        }
        return dict.map { (emoji: $0.key, count: $0.value.0, mine: $0.value.1) }
            .sorted { $0.emoji < $1.emoji }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 既についているリアクション
            if !counts.isEmpty {
                HStack(spacing: 6) {
                    ForEach(counts, id: \.emoji) { item in
                        Button { toggle(item.emoji) } label: {
                            HStack(spacing: 3) {
                                Text(item.emoji).font(.footnote)
                                Text("\(item.count)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(item.mine ? .white : .secondary)
                            }
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(item.mine ? AnyShapeStyle(AppPalette.accent)
                                                  : AnyShapeStyle(Color.gray.opacity(0.14)),
                                        in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            // リアクションを追加
            HStack(spacing: 8) {
                ForEach(Self.choices, id: \.self) { emoji in
                    Button { toggle(emoji) } label: {
                        Text(emoji)
                            .font(.title3)
                            .padding(6)
                            .background(Color.gray.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if !reactions.isEmpty {
                Text(reactions.compactMap(\.authorName).uniqued().joined(separator: "、")
                     + " が反応しました")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    /// 同じ絵文字を自分が既に付けていれば取り消し、なければ追加
    private func toggle(_ emoji: String) {
        if let existing = reactions.first(where: {
            $0.emoji == emoji && $0.authorName != nil && $0.authorName == myName
        }) {
            context.delete(existing)
        } else {
            let r = Reaction(context: context)
            r.id = UUID()
            r.emoji = emoji
            r.createdAt = Date()
            r.authorName = myName
            r.place = place
        }
        try? context.save()
    }
}

extension Sequence where Element: Hashable {
    /// 順序を保った重複除去
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
