import SwiftUI
import CoreData
import CoreLocation
import PhotosUI

struct AddEditPlaceView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: StoreManager

    let log: TravelLog
    let coordinate: CLLocationCoordinate2D
    let place: Place?          // nil なら新規追加
    let members: [Member]
    var initialName: String = ""   // 検索候補から引き継ぐ場所名

    @State private var name = ""
    @State private var isJapan = true
    @State private var year: Int = 0
    @State private var visitDate: Date? = nil
    @State private var hasDate = false
    @State private var hasEndDate = false
    @State private var visitEndDate: Date? = nil
    @State private var selectedIDs: Set<UUID> = []

    // コメント(無料) / 写真(プレミアム)
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var pendingImages: [Data] = []      // 圧縮済み。保存時に Attachment 化
    @State private var pendingComments: [String] = []  // 追加予定コメント
    @State private var newComment = ""
    @State private var showPaywall = false
    @State private var viewerIndex: Int?
    @State private var showDiscardConfirm = false
    @State private var importingCount = 0   // 取り込み中の総枚数
    @State private var importedCount = 0    // 取り込み済み枚数
    @State private var isLoaded = false     // load完了後だけ自動保存する

    /// 保存されていない入力があるか(誤って閉じて消えるのを防ぐ判定)
    private var hasUnsavedInput: Bool {
        !pendingImages.isEmpty
            || !pendingComments.isEmpty
            || !newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    /// リアクションの署名に使う自分の名前(設定した「自分」のメンバー名)
    private var myMemberName: String? {
        guard let idString = UserDefaults.standard.string(forKey: "myMemberID"),
              let id = UUID(uuidString: idString) else { return members.first?.displayName }
        return members.first { $0.id == id }?.displayName ?? members.first?.displayName
    }

    /// 既存のコメント(タイムライン: 新しい順)
    private var existingComments: [Attachment] {
        guard let set = place?.attachments as? Set<Attachment> else { return [] }
        return set.filter { $0.imageData == nil && !($0.comment ?? "").isEmpty }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    /// 既存の写真(新しい順)
    private var existingPhotos: [Attachment] {
        guard let set = place?.attachments as? Set<Attachment> else { return [] }
        return set.filter { $0.imageData != nil }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("場所") {
                    TextField("都市・スポット名", text: $name)
                    Picker("区分", selection: $isJapan) {
                        Text(AppRegion.homeLabel).tag(true)
                        Text(AppRegion.abroadLabel).tag(false)
                    }
                    .pickerStyle(.segmented)
                }

                Section("行った人") {
                    if members.isEmpty {
                        Text("メンバー画面から登録してください")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(members, id: \.objectID) { m in
                        if let id = m.id {
                            Button {
                                if selectedIDs.contains(id) { selectedIDs.remove(id) }
                                else { selectedIDs.insert(id) }
                            } label: {
                                HStack {
                                    Circle().fill(m.color).frame(width: 12, height: 12)
                                    Text(m.displayName).foregroundStyle(.primary)
                                    Spacer()
                                    if selectedIDs.contains(id) {
                                        Image(systemName: "checkmark").foregroundStyle(AppPalette.accent)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("いつ") {
                    Picker("訪問年", selection: $year) {
                        Text("未設定").tag(0)
                        ForEach((1975...currentYear).reversed(), id: \.self) { y in
                            Text("\(String(y))年").tag(y)
                        }
                    }
                    Toggle("詳しい日付を入れる", isOn: $hasDate)
                    if hasDate {
                        DatePicker("行った日",
                                   selection: Binding(get: { visitDate ?? Date() },
                                                      set: { visitDate = $0; year = Calendar.current.component(.year, from: $0) }),
                                   displayedComponents: .date)
                        Toggle("泊まりの旅(期間で記録)", isOn: $hasEndDate)
                        if hasEndDate {
                            DatePicker("帰った日",
                                       selection: Binding(get: { visitEndDate ?? visitDate ?? Date() },
                                                          set: { visitEndDate = $0 }),
                                       in: (visitDate ?? Date())...,
                                       displayedComponents: .date)
                            if let s = visitDate, let e = visitEndDate, e > s {
                                let nights = Calendar.current.dateComponents([.day], from: s, to: e).day ?? 0
                                Text("\(nights)泊\(nights + 1)日の旅")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let place {
                    Section {
                        ReactionBar(place: place, myName: myMemberName)
                            .padding(.vertical, 6)
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                            .listRowBackground(Color.clear)
                    }
                }

                commentSection
                photoSection

                if place != nil {
                    Section {
                        Button("この記録を削除", role: .destructive) {
                            if let place { context.delete(place); try? context.save() }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(place == nil ? "訪問地を追加" : "記録を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(place == nil ? "キャンセル" : "閉じる") {
                        if place != nil {
                            commitPendingAttachments(); autosave(); dismiss()
                        } else if hasUnsavedInput {
                            showDiscardConfirm = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(place == nil ? "保存" : "完了") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .interactiveDismissDisabled(hasUnsavedInput)
            .onAppear(perform: load)
            // 既存の記録は入力が変わるたび自動保存(保存ボタンを押し忘れても消えない)
            .onChange(of: formSignature) { _, _ in autosave() }
            .onChange(of: photoItems) { _, items in Task { await importPickedPhotos(items) } }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .confirmationDialog("入力した内容を破棄しますか?", isPresented: $showDiscardConfirm,
                                titleVisibility: .visible) {
                Button("保存する") { save() }
                Button("破棄する", role: .destructive) { dismiss() }
                Button("編集を続ける", role: .cancel) {}
            }
            .fullScreenCover(item: Binding(
                get: { viewerIndex.map { ViewerTarget(index: $0) } },
                set: { viewerIndex = $0?.index }
            )) { target in
                PhotoViewer(images: allPhotoImages,
                            captions: (0..<allPhotoImages.count).map { photoAuthor(at: $0) },
                            index: min(target.index, max(0, allPhotoImages.count - 1))) { i in
                    deletePhoto(at: i)
                }
            }
        }
    }

    private struct ViewerTarget: Identifiable {
        let index: Int
        var id: Int { index }
    }

    /// 自動保存の判定に使う入力の指紋(まとめて監視して型チェック負荷を下げる)
    private var formSignature: String {
        let ids = selectedIDs.map(\.uuidString).sorted().joined(separator: ",")
        let start = visitDate?.timeIntervalSince1970 ?? -1
        let end = visitEndDate?.timeIntervalSince1970 ?? -1
        return "\(name)|\(isJapan)|\(year)|\(hasDate)|\(hasEndDate)|\(start)|\(end)|\(ids)"
    }

    /// 既存の記録に対する自動保存(新規追加時は「保存」を押すまで作らない)
    private func autosave() {
        guard let p = place, isLoaded else { return }
        p.name = name.trimmingCharacters(in: .whitespaces)
        p.isJapan = isJapan
        p.year = Int16(year)
        p.visitDate = hasDate ? visitDate : nil
        p.visitEndDate = (hasDate && hasEndDate) ? visitEndDate : nil
        p.visitorIDList = Array(selectedIDs)
        try? context.save()
    }

    /// ビューアからの削除(追加予定分と保存済み分を通し番号で扱う)
    private func deletePhoto(at index: Int) {
        if index < pendingImages.count {
            pendingImages.remove(at: index)
        } else {
            let i = index - pendingImages.count
            guard i < existingPhotos.count else { return }
            context.delete(existingPhotos[i])
            try? context.save()
        }
    }

    // MARK: - コメント(無料)

    private var commentSection: some View {
        Section("コメント") {
            // 追加予定コメント
            ForEach(Array(pendingComments.enumerated()), id: \.offset) { i, text in
                HStack {
                    Image(systemName: "text.bubble").foregroundStyle(.secondary)
                    Text(text)
                    Spacer()
                    Button { pendingComments.remove(at: i) } label: {
                        Image(systemName: "minus.circle").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            // 既存コメントのタイムライン
            ForEach(existingComments, id: \.objectID) { att in
                VStack(alignment: .leading, spacing: 2) {
                    Text(att.commentText)
                    HStack(spacing: 6) {
                        if let who = att.authorName, !who.isEmpty {
                            Text(who)
                                .font(.caption2.bold())
                                .foregroundStyle(AppPalette.accent)
                        }
                        if let d = att.createdAt {
                            Text(d.jaDateText)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { offsets in
                offsets.map { existingComments[$0] }.forEach(context.delete)
                try? context.save()
            }
            HStack {
                TextField("思い出やひとことを", text: $newComment, axis: .vertical)
                    .lineLimit(1...3)
                Button("追加") {
                    let t = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !t.isEmpty else { return }
                    pendingComments.append(t)
                    newComment = ""
                    // 既存の記録なら即反映(保存ボタン不要)
                    if place != nil { commitPendingAttachments() }
                }
                .disabled(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    // MARK: - 写真(プレミアム)

    @ViewBuilder
    private var photoSection: some View {
        Section {
            if store.isPremium {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("写真", systemImage: "photo.on.rectangle.angled")
                            .font(.subheadline.bold())
                        Spacer()
                        if !allPhotoImages.isEmpty {
                            Text("\(allPhotoImages.count)枚")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    if importingCount > 0 {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("写真を読み込み中… \(importedCount)/\(importingCount)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color(hex: "FFF6EA"), in: RoundedRectangle(cornerRadius: 14))
                    }

                    if allPhotoImages.isEmpty && importingCount == 0 {
                        PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .images) {
                            VStack(spacing: 8) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 30))
                                    .foregroundStyle(AppPalette.accent)
                                Text("写真を追加")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(AppPalette.accent)
                                Text("この場所の思い出を残そう")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(hex: "FFF6EA"))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(AppPalette.accent.opacity(0.3),
                                                  style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                            )
                        }
                    } else {
                        photoGrid
                        PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .images) {
                            Label("写真を追加", systemImage: "plus")
                                .font(.footnote.bold())
                                .foregroundStyle(AppPalette.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(AppPalette.accent.opacity(0.1),
                                            in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding(.vertical, 4)
                .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
            } else {
                Button { showPaywall = true } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(AppPalette.accent.opacity(0.12))
                                .frame(width: 52, height: 52)
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 21))
                                .foregroundStyle(AppPalette.accent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("写真を残す").font(.subheadline.bold()).foregroundStyle(.primary)
                            Text("プレミアムで思い出の写真を無制限に")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// SNS風の写真グリッド。1枚なら大きく、複数なら2列
    @ViewBuilder
    private var photoGrid: some View {
        let images = allPhotoImages
        if images.count == 1 {
            photoTile(images[0], index: 0, height: 240)
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                      spacing: 6) {
                ForEach(Array(images.enumerated()), id: \.offset) { i, img in
                    photoTile(img, index: i, height: 130)
                }
            }
        }
    }

    private func photoTile(_ image: UIImage, index: Int, height: CGFloat) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .topLeading) {
                // 削除ボタン
                Button {
                    deletePhoto(at: index)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(7)
            }
            .overlay(alignment: .topTrailing) {
                // 保存前の写真には印をつける
                if index < pendingImages.count {
                    Text("新規")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(AppPalette.accent, in: Capsule())
                        .padding(7)
                }
            }
            .overlay(alignment: .bottomLeading) {
                // 誰が上げた写真かを表示
                if let who = photoAuthor(at: index) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill").font(.system(size: 8, weight: .bold))
                        Text(who).font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.42), in: Capsule())
                    .padding(7)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .onTapGesture { viewerIndex = index }
    }

    /// 通し番号から写真の投稿者名を返す
    private func photoAuthor(at index: Int) -> String? {
        if index < pendingImages.count {
            return myMemberName   // これから保存する分は自分
        }
        let i = index - pendingImages.count
        guard i < existingPhotos.count else { return nil }
        return existingPhotos[i].authorName
    }

    /// 追加予定+保存済みの全写真
    private var allPhotoImages: [UIImage] {
        pendingImages.compactMap(UIImage.init(data:)) + existingPhotos.compactMap(\.image)
    }

    private func importPickedPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        importingCount = items.count
        defer { importingCount = 0 }

        // 読み込みと圧縮を並列＋バックグラウンドで行う。
        // (以前は1枚ずつ逐次、しかも圧縮がUIスレッドを塞いでいた)
        let results: [(Int, Data)] = await withTaskGroup(of: (Int, Data)?.self) { group in
            for (i, item) in items.enumerated() {
                group.addTask {
                    guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
                    // 重いデコード・リサイズ・JPEG化はメインスレッドから外す
                    guard let jpeg = await Self.compress(data) else { return nil }
                    return (i, jpeg)
                }
            }
            var collected: [(Int, Data)] = []
            for await r in group {
                if let r {
                    collected.append(r)
                    importedCount = collected.count
                }
            }
            return collected
        }

        // 選んだ順を保つ
        pendingImages.append(contentsOf: results.sorted { $0.0 < $1.0 }.map(\.1))
        importedCount = 0
        photoItems = []
        // 既存の記録なら選んだ時点で保存(保存ボタンを押さなくても反映される)
        if place != nil { commitPendingAttachments() }
    }

    /// 追加待ちの写真・コメントをその場で保存する(既存の記録のみ)
    private func commitPendingAttachments() {
        guard let p = place, !pendingImages.isEmpty || !pendingComments.isEmpty else { return }
        let now = Date()
        for text in pendingComments {
            let att = Attachment(context: context)
            att.id = UUID(); att.createdAt = now
            att.comment = text; att.authorName = myMemberName; att.place = p
        }
        if store.isPremium {
            for data in pendingImages {
                let att = Attachment(context: context)
                att.id = UUID(); att.createdAt = now
                att.imageData = data; att.authorName = myMemberName; att.place = p
            }
        }
        pendingComments.removeAll()
        pendingImages.removeAll()
        try? context.save()
    }

    /// バックグラウンドで画像を圧縮する
    private static func compress(_ data: Data) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            UIImage(data: data)?.compressedJPEGData()
        }.value
    }

    // MARK: - 読み込み / 保存

    private func load() {
        defer { isLoaded = true }
        if let p = place {
            name = p.name ?? ""
            isJapan = p.isJapan
            year = Int(p.year)
            visitDate = p.visitDate
            hasDate = p.visitDate != nil
            visitEndDate = p.visitEndDate
            hasEndDate = p.visitEndDate != nil
            selectedIDs = Set(p.visitorIDList)
        } else {
            // 年は「今年」を初期値に(未設定のまま保存されるのを防ぐ)
            year = currentYear
            // 「行った人」は前回の選択を初期値にする(存在するメンバーのみ)
            let last = UserDefaults.standard.stringArray(forKey: "lastVisitorIDs") ?? []
            let validIDs = Set(members.compactMap(\.id))
            let restored = Set(last.compactMap(UUID.init(uuidString:))).intersection(validIDs)
            if !restored.isEmpty {
                selectedIDs = restored
            } else if members.count == 1, let id = members[0].id {
                selectedIDs = [id]
            }
            // 検索候補から来た場合はその名前を優先
            if !initialName.isEmpty { name = initialName }
            // 逆ジオコーディングで名前(未設定時)と国内/海外を推定
            let loc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            CLGeocoder().reverseGeocodeLocation(loc, preferredLocale: AppRegion.preferredLocale) { marks, _ in
                guard let m = marks?.first else { return }
                if name.isEmpty { name = m.locality ?? m.administrativeArea ?? m.name ?? "" }
                isJapan = (m.isoCountryCode == AppRegion.homeISOCode)
            }
        }
    }

    private func save() {
        let p = place ?? Place(context: context)
        if place == nil {
            p.id = UUID()
            p.createdAt = Date()
            p.latitude = coordinate.latitude
            p.longitude = coordinate.longitude
            p.log = log
        }
        p.name = name.trimmingCharacters(in: .whitespaces)
        p.isJapan = isJapan
        p.year = Int16(year)
        p.visitDate = hasDate ? visitDate : nil
        p.visitEndDate = (hasDate && hasEndDate) ? visitEndDate : nil
        p.visitorIDList = Array(selectedIDs)
        // 次回の初期選択用に記憶(新規登録時のみ)
        if place == nil {
            UserDefaults.standard.set(selectedIDs.map(\.uuidString), forKey: "lastVisitorIDs")
        }

        let now = Date()
        // コメント(無料)
        for text in pendingComments {
            let att = Attachment(context: context)
            att.id = UUID()
            att.createdAt = now
            att.comment = text
            att.authorName = myMemberName
            att.place = p
        }
        // 入力欄に残っている未追加のコメントも保存
        let leftover = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !leftover.isEmpty {
            let att = Attachment(context: context)
            att.id = UUID()
            att.createdAt = now
            att.comment = leftover
            att.authorName = myMemberName
            att.place = p
        }
        // 写真(プレミアムのみ)
        if store.isPremium {
            for data in pendingImages {
                let att = Attachment(context: context)
                att.id = UUID()
                att.createdAt = now
                att.imageData = data
                att.authorName = myMemberName
                att.place = p
            }
        }

        try? context.save()
        dismiss()
    }
}
