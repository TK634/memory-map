import SwiftUI
import CoreData

/// 場所へのリアクション(スタンプ)。共有相手の記録に反応でき、見るだけの人も参加できる
struct ReactionBar: View {
    @Environment(\.managedObjectContext) private var context
    let place: Place
    /// 自分の名前(メンバー名。未設定なら nil)
    let myName: String?
    /// 押した人のアイコンの色に使う
    var members: [Member] = []

    /// よく使う6つ(常に表示)
    static let choices = ["❤️", "👍", "😊", "🎉", "🍜", "📸"]

    /// カテゴリ別の全スタンプ(「もっと」で表示)
    static let categories: [(name: String, icon: String, emojis: [String])] = [
        ("きもち", "heart.fill",
         ["❤️", "😍", "🥰", "😊", "😆", "🤩", "👍", "👏", "🙌", "✨", "💯", "🥺", "😭", "🤣", "😴", "🫶"]),
        ("たべる", "fork.knife",
         ["🍜", "🍣", "🍱", "🍰", "🍦", "🍺", "☕️", "🍕", "🍖", "🥟", "🍧", "🍹", "🍶", "🧁", "🍩", "🥐"]),
        ("たび", "airplane",
         ["✈️", "🚄", "🚗", "⛴️", "🗼", "⛩️", "🏯", "🏝️", "🗻", "🏔️", "🌊", "🎢", "🏨", "🚌", "🧳", "🗺️"]),
        ("しぜん", "leaf.fill",
         ["🌸", "🍁", "🌻", "❄️", "☀️", "🌈", "🌙", "⭐️", "🌷", "🍀", "🌲", "🦌", "🐟", "🐈", "🌅", "🎇"]),
        ("イベント", "party.popper.fill",
         ["🎉", "🎊", "🎂", "🎁", "💐", "🎄", "🎃", "🎆", "💍", "👶", "🎓", "🏆", "🎤", "⚽️", "🎡", "🛍️"]),
    ]

    @State private var poppingEmoji: String?      // 押した瞬間に弾ませる対象
    @State private var floatingEmoji: String?     // ふわっと浮かぶ演出
    @State private var floatID = UUID()
    @State private var showAllStamps = false

    /// 起動引数でスタンプ選択シートを自動表示(デザイン確認用)
    private var autoOpenPicker: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-openStampPicker")
        #else
        false
        #endif
    }

    private var reactions: [Reaction] {
        ((place.reactions as? Set<Reaction>) ?? [])
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    /// 絵文字ごとの集計(付与順)。押した人の名前も持つ
    private var summary: [(emoji: String, count: Int, mine: Bool, authors: [String?])] {
        var order: [String] = []
        var dict: [String: [Reaction]] = [:]
        for r in reactions {
            guard let e = r.emoji else { continue }
            if dict[e] == nil { order.append(e) }
            dict[e, default: []].append(r)
        }
        return order.compactMap { e in
            guard let rs = dict[e] else { return nil }
            let mine = rs.contains { $0.authorName != nil && $0.authorName == myName }
            return (emoji: e, count: rs.count, mine: mine, authors: rs.map(\.authorName))
        }
    }

    private func color(for author: String?) -> Color {
        guard let author else { return .gray.opacity(0.45) }
        return members.first { $0.displayName == author }?.color ?? AppPalette.accent
    }

    /// 手前に出す6つ: 最近使ったスタンプを優先し、足りない分は既定から補う
    private var quickStamps: [String] {
        let recent = UserDefaults.standard.stringArray(forKey: "recentStamps") ?? []
        return Array((recent + Self.choices).uniqued().prefix(6))
    }

    /// 使ったスタンプを履歴の先頭へ
    private func rememberStamp(_ emoji: String) {
        let recent = UserDefaults.standard.stringArray(forKey: "recentStamps") ?? []
        let updated = Array(([emoji] + recent).uniqued().prefix(12))
        UserDefaults.standard.set(updated, forKey: "recentStamps")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 付いているリアクション(スタンプ+押した人のアイコン+人数)
            if !summary.isEmpty {
                FlowRow(spacing: 8) {
                    ForEach(summary, id: \.emoji) { item in
                        reactionChip(item)
                    }
                }
            }

            // 押せるスタンプ(よく使う6つ+もっと)
            HStack(spacing: 4) {
                ForEach(quickStamps, id: \.self) { emoji in
                    stampButton(emoji)
                }
                Button { showAllStamps = true } label: {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppPalette.accent)
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(AppPalette.accent)
                                .background(Circle().fill(.white))
                                .offset(x: 5, y: -4)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(PressableStyle())
            }
            .overlay(alignment: .top) {
                // 押したスタンプがふわっと浮き上がる
                if let floatingEmoji {
                    Text(floatingEmoji)
                        .font(.system(size: 34))
                        .modifier(FloatUpEffect())
                        .id(floatID)
                        .allowsHitTesting(false)
                }
            }

            if summary.isEmpty {
                Text("スタンプで思い出に反応しよう")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if autoOpenPicker {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { showAllStamps = true }
            }
        }
        .sheet(isPresented: $showAllStamps) {
            StampPickerView(myEmojis: Set(summary.filter(\.mine).map(\.emoji))) { emoji in
                toggle(emoji)
            }
            .presentationDetents([.medium, .large])
        }
    }

    /// 押せるスタンプ。自分が押したものはやわらかいオレンジの丸で囲む
    private func stampButton(_ emoji: String) -> some View {
        let mine = summary.first { $0.emoji == emoji }?.mine ?? false
        return Button {
            toggle(emoji)
        } label: {
            Text(emoji)
                .font(.system(size: 26))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    Circle()
                        .fill(AppPalette.accent.opacity(mine ? 0.18 : 0))
                        .frame(width: 42, height: 42)
                )
                .scaleEffect(poppingEmoji == emoji ? 1.35 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.45), value: poppingEmoji)
        }
        .buttonStyle(.plain)
    }

    /// 付いたリアクション: スタンプ・押した人の頭文字アイコン(重ねて表示)・人数
    private func reactionChip(_ item: (emoji: String, count: Int, mine: Bool, authors: [String?])) -> some View {
        let shown = Array(item.authors.prefix(3))
        return Button { toggle(item.emoji) } label: {
            HStack(spacing: 6) {
                Text(item.emoji).font(.system(size: 17))
                HStack(spacing: -7) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { _, author in
                        Group {
                            if let author, !author.isEmpty {
                                MemberAvatar(name: author, color: color(for: author), size: 22)
                            } else {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(Color.gray.opacity(0.45), in: Circle())
                            }
                        }
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
                Text(item.count > 3 ? "+\(item.count - 3)" : "\(item.count)")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(item.mine ? AppPalette.accent : AppPalette.chrome.opacity(0.7))
            }
            .padding(.leading, 10).padding(.trailing, 12).padding(.vertical, 6)
            .background(item.mine ? AppPalette.accent.opacity(0.12) : Color.gray.opacity(0.07),
                        in: Capsule())
            .overlay(Capsule().stroke(item.mine ? AppPalette.accent.opacity(0.6) : .clear, lineWidth: 1.5))
        }
        .buttonStyle(PressableStyle())
        .transition(.scale.combined(with: .opacity))
    }

    /// 同じ絵文字を自分が既に付けていれば取り消し、なければ追加
    private func toggle(_ emoji: String) {
        let hadMine = reactions.first {
            $0.emoji == emoji && $0.authorName != nil && $0.authorName == myName
        }

        // 押した感触(触覚+弾み)
        UIImpactFeedbackGenerator(style: hadMine == nil ? .medium : .light).impactOccurred()
        poppingEmoji = emoji
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            if poppingEmoji == emoji { poppingEmoji = nil }
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            if let hadMine {
                context.delete(hadMine)
            } else {
                let r = Reaction(context: context)
                r.id = UUID()
                r.emoji = emoji
                r.createdAt = Date()
                r.authorName = myName
                r.place = place
                rememberStamp(emoji)
                // 追加時だけ浮き上がる演出
                floatID = UUID()
                floatingEmoji = emoji
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    if floatingEmoji == emoji { floatingEmoji = nil }
                }
            }
        }
        try? context.save()
    }
}

/// カテゴリ別のスタンプ選択シート
struct StampPickerView: View {
    @Environment(\.dismiss) private var dismiss
    /// 自分が既に付けているスタンプ(チェック表示用)
    let myEmojis: Set<String>
    let onSelect: (String) -> Void

    @State private var categoryIndex = 0

    private var categories: [(name: String, icon: String, emojis: [String])] {
        ReactionBar.categories
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // カテゴリタブ
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(categories.enumerated()), id: \.offset) { i, cat in
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) { categoryIndex = i }
                            } label: {
                                Label(cat.name, systemImage: cat.icon)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(categoryIndex == i
                                                ? AnyShapeStyle(AppPalette.accent)
                                                : AnyShapeStyle(Color.gray.opacity(0.12)),
                                                in: Capsule())
                                    .foregroundStyle(categoryIndex == i ? .white : AppPalette.chrome)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                // スタンプ一覧
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5),
                              spacing: 14) {
                        ForEach(categories[categoryIndex].emojis, id: \.self) { emoji in
                            Button {
                                onSelect(emoji)
                                dismiss()
                            } label: {
                                Text(emoji)
                                    .font(.system(size: 30))
                                    .frame(width: 56, height: 56)
                                    .background(
                                        Circle().fill(.white)
                                            .shadow(color: .black.opacity(0.07), radius: 3, y: 2)
                                    )
                                    .overlay(
                                        Circle().stroke(AppPalette.accent,
                                                        lineWidth: myEmojis.contains(emoji) ? 2.5 : 0)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .background(
                LinearGradient(colors: [Color(hex: "FFF8EF"), Color(hex: "FFF1E0")],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            )
            .navigationTitle("スタンプを選ぶ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
        }
    }
}

/// スタンプがふわっと上に浮かんで消える演出
private struct FloatUpEffect: ViewModifier {
    @State private var animating = false

    func body(content: Content) -> some View {
        content
            .offset(y: animating ? -46 : 4)
            .opacity(animating ? 0 : 1)
            .scaleEffect(animating ? 1.4 : 0.7)
            .onAppear {
                withAnimation(.easeOut(duration: 0.85)) { animating = true }
            }
    }
}

extension Sequence where Element: Hashable {
    /// 順序を保った重複除去
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
