import Foundation
import Combine
import StoreKit

/// StoreKit 2 でサブスク(プレミアム)を管理する。
/// - 商品読み込み / 購入 / 復元 / 課金状態の監視
/// - `isPremium` を監視して UI 側で機能を出し分ける
@MainActor
final class StoreManager: ObservableObject {

    /// App Store Connect で作成するサブスク商品ID(TODO/DESIGN と一致させること)
    static let premiumProductID = "ashiato.premium.monthly"

    @Published private(set) var product: Product?
    @Published private(set) var isPremium = false
    @Published private(set) var isLoadingProducts = false
    @Published var purchaseError: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        // アプリ生存中ずっとトランザクション更新を監視(購入・返金・他デバイスでの購入を反映)
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                await self.handle(transactionResult: result)
                await self.refreshPremiumStatus()
            }
        }
        Task {
            await loadProducts()
            await refreshPremiumStatus()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    /// 表示用の価格文字列(例: "¥300")。読み込み前は nil
    var displayPrice: String? { product?.displayPrice }

    // MARK: - 商品読み込み

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let products = try await Product.products(for: [Self.premiumProductID])
            product = products.first
        } catch {
            purchaseError = "商品情報の取得に失敗しました。通信環境をご確認ください。"
        }
    }

    // MARK: - 購入

    /// 戻り値: 購入が完了したら true(承認待ち・キャンセルは false)
    @discardableResult
    func purchase() async -> Bool {
        guard let product else {
            await loadProducts()
            guard product != nil else {
                purchaseError = "商品を読み込めませんでした。時間をおいて再度お試しください。"
                return false
            }
            return await purchase()
        }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await handle(transactionResult: verification)
                await refreshPremiumStatus()
                return isPremium
            case .userCancelled:
                return false
            case .pending:
                purchaseError = "購入が承認待ちです。承認後にプレミアムが有効になります。"
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseError = "購入処理に失敗しました。"
            return false
        }
    }

    // MARK: - 復元

    func restore() async {
        do {
            try await AppStore.sync()
            await refreshPremiumStatus()
            if !isPremium {
                purchaseError = "復元できる購入が見つかりませんでした。"
            }
        } catch {
            purchaseError = "購入の復元に失敗しました。"
        }
    }

    // MARK: - 状態監視

    /// 現在有効な権利を確認して isPremium を更新
    func refreshPremiumStatus() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.premiumProductID,
               transaction.revocationDate == nil {
                active = true
            }
        }
        isPremium = active
    }

    /// 検証済みトランザクションを finish する
    private func handle(transactionResult: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = transactionResult else { return }
        await transaction.finish()
    }
}
