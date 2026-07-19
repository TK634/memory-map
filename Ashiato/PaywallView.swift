import SwiftUI

/// プレミアム(サブスク)のペイウォール。
/// 審査対策として「継続的価値」(写真・コメント無制限+今後の機能追加)を明示する。
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: StoreManager

    @State private var isWorking = false

    private struct Benefit: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
    }

    private let benefits: [Benefit] = [
        .init(icon: "photo.on.rectangle.angled",
              title: "場所ごとの写真",
              detail: "訪れた場所に思い出の写真を無制限に残せます。"),
        .init(icon: "text.bubble",
              title: "コメントのタイムライン",
              detail: "行くたびにコメントを追記。ふたりの記録が積み重なります。"),
        .init(icon: "sparkles",
              title: "今後の新機能を先行提供",
              detail: "月別グラフや訪問国カウントなど、追加機能をいち早く。"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    VStack(spacing: 16) {
                        ForEach(benefits) { b in benefitRow(b) }
                    }
                    .padding(.horizontal, 4)

                    subscribeButton
                    footer
                }
                .padding(20)
            }
            .navigationTitle("プレミアム")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .onChange(of: store.isPremium) { _, premium in
                if premium { dismiss() }
            }
            .alert("お知らせ", isPresented: Binding(
                get: { store.purchaseError != nil },
                set: { if !$0 { store.purchaseError = nil } })) {
                Button("OK", role: .cancel) { store.purchaseError = nil }
            } message: {
                Text(store.purchaseError ?? "")
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "map.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.white, AppPalette.accent)
            Text("思い出をもっと豊かに")
                .font(.title2.bold())
            Text("写真とコメントで、地図の一つひとつのピンに物語を。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private func benefitRow(_ b: Benefit) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: b.icon)
                .font(.title3)
                .foregroundStyle(AppPalette.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(b.title).font(.subheadline.bold())
                Text(b.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var subscribeButton: some View {
        VStack(spacing: 8) {
            Button {
                Task {
                    isWorking = true
                    await store.purchase()
                    isWorking = false
                }
            } label: {
                HStack {
                    if isWorking { ProgressView().tint(.white) }
                    Text(subscribeLabel)
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppPalette.chrome, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
            }
            .disabled(isWorking || store.isLoadingProducts)

            Button("購入を復元") {
                Task {
                    isWorking = true
                    await store.restore()
                    isWorking = false
                }
            }
            .font(.footnote)
            .disabled(isWorking)
        }
    }

    private var subscribeLabel: String {
        if let price = store.displayPrice {
            return "1週間無料で試す(その後 \(price)/月)"
        }
        return store.isLoadingProducts ? "読み込み中…" : "プレミアムを始める"
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Text("いつでも解約できます。無料トライアル終了の24時間前までに解約すると課金されません。")
            Text("お支払いはApple IDに請求され、解約しない限り自動更新されます。")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.top, 4)
    }
}
