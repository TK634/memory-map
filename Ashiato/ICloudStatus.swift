import SwiftUI
import Combine
import CloudKit
import UIKit

/// iCloud(このアプリのコンテナ)が使えるかどうか。
/// あしあとはログインの代わりに iPhone の Apple ID(iCloud)を使うため、
/// 未サインインだと記録がその iPhone にしか残らず、共有もできない。
@MainActor
final class ICloudStatus: ObservableObject {
    static let shared = ICloudStatus()

    @Published private(set) var status: CKAccountStatus = .couldNotDetermine
    /// 一度でも確認できたか(確認前は案内を出さない)
    @Published private(set) var checked = false

    private var observer: NSObjectProtocol?

    private init() {
        // 設定アプリでサインイン・サインアウトしたら確認し直す
        observer = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { _ in
            Task { @MainActor in await ICloudStatus.shared.refresh() }
        }
    }

    var isAvailable: Bool { status == .available }

    /// 案内を出すべき状態か(確認できていて、使えない)
    var needsGuide: Bool { checked && !isAvailable }

    func refresh() async {
        // iCloud を使わない設定のビルド(entitlements なし)では案内しない
        guard PersistenceController.shared.isCloudEnabled else {
            status = .available; checked = true; return
        }
        do {
            status = try await CKContainer(identifier: PersistenceController.cloudKitContainerID).accountStatus()
        } catch {
            status = .couldNotDetermine
        }
        checked = true
    }

    /// 状態ごとの説明
    var message: String {
        switch status {
        case .noAccount:
            return String(localized: "このiPhoneはiCloudにサインインしていません。")
        case .restricted:
            return String(localized: "このiPhoneではiCloudの利用が制限されています(スクリーンタイムや管理の設定)。")
        case .temporarilyUnavailable:
            return String(localized: "iCloudの確認が必要です。設定アプリでApple IDのパスワードを入力し直してください。")
        default:
            return String(localized: "iCloudの状態を確認できませんでした。通信環境とiCloudのサインインを確認してください。")
        }
    }
}

// MARK: - 案内カード(カレンダーの上)

struct ICloudNoticeCard: View {
    var onOpen: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "icloud.slash.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color(hex: "5A8FD8"), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text("iCloudにサインインしませんか?")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppPalette.chrome)
                Text("今の記録はこのiPhoneの中だけにあります。サインインすると機種変更しても残り、恋人や家族と共有できます。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    Button("やり方を見る", action: onOpen)
                        .font(.caption.bold())
                    Button("あとで", action: onDismiss)
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - サインインのやり方

struct ICloudGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var icloud = ICloudStatus.shared
    /// 共有しようとして(または招待を開いて)案内が出たとき
    var reason: String? = nil

    var body: some View {
        NavigationStack {
            List {
                if icloud.isAvailable {
                    Section {
                        Label("iCloudにサインインできました", systemImage: "checkmark.icloud.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                        Text("これで記録がiCloudに保存され、共有もできます。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        if let reason {
                            Text(reason).font(.subheadline.bold())
                        }
                        Text(icloud.message)
                            .font(.subheadline)
                        VStack(alignment: .leading, spacing: 6) {
                            benefit("arrow.triangle.2.circlepath", "機種変更しても、記録と写真がそのまま残る")
                            benefit("person.2.fill", "恋人や家族を招待して、同じ地図に書き込める")
                            benefit("lock.fill", "記録はあなたのiCloudだけに保存(アカウント登録は不要)")
                        }
                        .padding(.vertical, 4)
                    }

                    Section("サインインのしかた") {
                        step(1, "「設定」アプリを開く")
                        step(2, "いちばん上の「iPhoneにサインイン」をタップし、Apple IDでサインイン")
                        step(3, "あなたの名前 →「iCloud」→「iCloudを使用しているApp」で「あしあと」がオンになっているか確認")
                    }

                    Section {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("設定アプリを開く", systemImage: "gearshape.fill")
                                .font(.subheadline.bold())
                        }
                    } footer: {
                        Text("「あしあと」の設定が開いたら、左上の「設定」に戻ってからサインインしてください。サインインしたらこのアプリに戻ると、自動で確認します。")
                    }
                }
            }
            .navigationTitle("iCloudで記録を守る")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } }
            }
            // 設定アプリから戻ってきたら確認し直す
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await icloud.refresh() } }
            }
            .task { await icloud.refresh() }
        }
    }

    private func benefit(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text).font(.caption)
        } icon: {
            Image(systemName: icon).foregroundStyle(AppPalette.accent)
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(AppPalette.accent, in: Circle())
            Text(text).font(.subheadline)
        }
        .padding(.vertical, 2)
    }
}
