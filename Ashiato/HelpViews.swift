import SwiftUI

// MARK: - 初回チュートリアル

struct OnboardingView: View {
    let onFinish: () -> Void
    /// 最後のページの「招待する」から呼ばれる
    var onInvite: (() -> Void)? = nil
    @State private var page = 0

    private let lastPage = 4

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                onboardPage(
                    icon: "shoeprints.fill",
                    iconColor: AppPalette.accent,
                    title: "あしあとへようこそ",
                    lines: ["行った場所に「あしあと」を残す地図アプリです。",
                            "旅行はもちろん、はじめて行ったお店や公園、休日のおでかけも。",
                            "積み重ねた場所が、ふたりの思い出の地図になります。"]
                ).tag(0)

                onboardPage(
                    icon: "magnifyingglass",
                    iconColor: AppPalette.chrome,
                    title: "検索して、えらぶだけ",
                    lines: ["下の「＋登録」ボタンから行った場所を検索して、候補から選ぶだけで記録できます。",
                            "泊まりの旅は期間でも記録できます。コメントもいっしょにどうぞ。"]
                ).tag(1)

                colorPage.tag(2)

                onboardPage(
                    icon: "person.2.fill",
                    iconColor: AppPalette.together,
                    title: "ふたりで共有",
                    lines: ["メンバー画面(人型ボタン)で家族や友達を登録。",
                            "招待すると、相手のiPhoneでも同じ地図を一緒に編集できます。"]
                ).tag(3)

                invitePage.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            if page == lastPage {
                // 最後は「招待する」を主ボタンに(みてね/TimeTree式: 招待を後回しにさせない)
                Button {
                    onFinish()
                    onInvite?()
                } label: {
                    Label("パートナーを招待する", systemImage: "person.badge.plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppPalette.accent, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 10)

                Button("あとで(ひとりではじめる)") { onFinish() }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)
            } else {
                Button {
                    withAnimation { page += 1 }
                } label: {
                    Text("次へ")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppPalette.chrome, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 10)

                Button("スキップ") { onFinish() }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)
            }
        }
        .interactiveDismissDisabled()
    }

    /// 招待を促す最終ページ
    private var invitePage: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "person.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(AppPalette.accent)
            Text("ひとりより、ふたりで").font(.title2.bold())
            VStack(spacing: 8) {
                Text("相手が記録した場所も同じ地図に集まります。")
                Text("「どこ行ったっけ?」がなくなり、次の行き先も決めやすくなります。")
                Text("招待はメッセージやLINEで送るだけ。相手の登録も不要です。")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
    }

    private func onboardPage(icon: String, iconColor: Color, title: String, lines: [String]) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundStyle(iconColor)
            Text(title).font(.title2.bold())
            VStack(spacing: 8) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
    }

    /// ピンの色の意味ページ
    private var colorPage: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "paintpalette.fill")
                .font(.system(size: 64))
                .foregroundStyle(AppPalette.partial)
            Text("ピンの色でひと目でわかる").font(.title2.bold())
            VStack(alignment: .leading, spacing: 14) {
                colorRow(AppPalette.memberColors.first.map { Color(hex: $0) } ?? .red,
                         "ひとりで行った場所", "そのメンバーの色")
                colorRow(AppPalette.together, "全員で行った場所", "みんなの思い出")
                colorRow(AppPalette.partial, "一部の人が行った場所", "次はみんなで行こう")
            }
            .padding(.horizontal, 40)
            Spacer()
            Spacer()
        }
    }

    private func colorRow(_ color: Color, _ title: String, _ sub: String) -> some View {
        HStack(spacing: 12) {
            PinView(color: color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.bold())
                Text(sub).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 使い方

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    var onReplayTutorial: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            List {
                Section("記録する") {
                    helpRow("plus.circle.fill", "登録ボタンから記録", "下の「＋登録」から「京都」「パリ」などを検索し、候補を選ぶと記録画面が開きます。")
                    helpRow("calendar", "日付・期間", "行った日に加えて「泊まりの旅」は帰った日まで期間で記録できます。")
                    helpRow("hand.tap", "ピンをタップ", "登録済みのピンをタップすると編集・コメント追記ができます。")
                    helpRow("text.bubble", "コメント", "場所ごとに何件でも。行くたびに思い出を追記できます。")
                    helpRow("photo.on.rectangle.angled", "写真(プレミアム)", "場所ごとに写真を残せます。記録画面から追加します。")
                }
                Section("ピンの色") {
                    helpColorRow(AppPalette.memberColors.first.map { Color(hex: $0) } ?? .red,
                                 "メンバーの色", "その人がひとりで行った場所")
                    helpColorRow(AppPalette.together, "緑", "全員で行った場所")
                    helpColorRow(AppPalette.partial, "紫", "一部の人が行った場所")
                    helpColorRow(AppPalette.none, "グレー", "誰が行ったか未設定")
                }
                Section("見る・しぼり込む") {
                    helpRow("line.3.horizontal.decrease.circle", "フィルター", "地図上部のチップで「行った人」「国内/海外」「年」をしぼり込み。")
                    helpRow("trophy", "ランキング", "メンバーごとの訪問数を比較。フィルターと連動します。")
                    helpRow("list.bullet", "一覧", "記録を新しい順に一覧表示。タップで地図へジャンプ。")
                    helpRow("rosette", "実績", "制県レベル(47都道府県)・訪問国数・バッジ。記録するほど増えていきます。")
                }
                Section("共有") {
                    helpRow("person.2", "メンバー登録", "人型ボタンから追加。名前と色を設定できます。")
                    helpRow("square.and.arrow.up", "iCloudで共有", "右上の共有ボタンから招待リンクを送信。相手も同じ地図を編集できます。")
                }
                if let onReplayTutorial {
                    Section {
                        Button {
                            onReplayTutorial()
                            dismiss()
                        } label: {
                            Label("チュートリアルをもう一度見る", systemImage: "play.circle.fill")
                                .foregroundStyle(AppPalette.accent)
                        }
                    }
                }
            }
            .navigationTitle("使い方")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
        }
    }

    private func helpRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AppPalette.accent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func helpColorRow(_ color: Color, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            PinView(color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
