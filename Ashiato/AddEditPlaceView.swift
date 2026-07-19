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

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }

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
                        Text("国内").tag(true)
                        Text("海外").tag(false)
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
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
            .onChange(of: photoItems) { _, items in Task { await importPickedPhotos(items) } }
            .sheet(isPresented: $showPaywall) { PaywallView() }
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
                    if let d = att.createdAt {
                        Text(d.jaDateText)
                            .font(.caption2).foregroundStyle(.secondary)
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
                }
                .disabled(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    // MARK: - 写真(プレミアム)

    @ViewBuilder
    private var photoSection: some View {
        Section("写真") {
            if store.isPremium {
                if !existingPhotos.isEmpty || !pendingImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            // 追加予定の写真
                            ForEach(Array(pendingImages.enumerated()), id: \.offset) { i, data in
                                ZStack(alignment: .topTrailing) {
                                    if let ui = UIImage(data: data) {
                                        Image(uiImage: ui).resizable().scaledToFill()
                                            .frame(width: 72, height: 72)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    Button { pendingImages.remove(at: i) } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.white, .black.opacity(0.5))
                                    }
                                    .padding(2)
                                }
                            }
                            // 既存の写真
                            ForEach(existingPhotos, id: \.objectID) { att in
                                ZStack(alignment: .topTrailing) {
                                    if let ui = att.image {
                                        Image(uiImage: ui).resizable().scaledToFill()
                                            .frame(width: 72, height: 72)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    Button {
                                        context.delete(att)
                                        try? context.save()
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.white, .black.opacity(0.5))
                                    }
                                    .padding(2)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                PhotosPicker(selection: $photoItems, maxSelectionCount: 5, matching: .images) {
                    Label("写真を追加", systemImage: "photo.on.rectangle.angled")
                }
            } else {
                Button { showPaywall = true } label: {
                    HStack {
                        Image(systemName: "lock.fill").foregroundStyle(AppPalette.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("写真を追加").foregroundStyle(.primary)
                            Text("プレミアムで思い出の写真を残せます")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func importPickedPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let ui = UIImage(data: data),
                  let jpeg = ui.compressedJPEGData() else { continue }
            await MainActor.run { pendingImages.append(jpeg) }
        }
        await MainActor.run { photoItems = [] }
    }

    // MARK: - 読み込み / 保存

    private func load() {
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
            CLGeocoder().reverseGeocodeLocation(loc, preferredLocale: Locale(identifier: "ja_JP")) { marks, _ in
                guard let m = marks?.first else { return }
                if name.isEmpty { name = m.locality ?? m.administrativeArea ?? m.name ?? "" }
                isJapan = (m.isoCountryCode == "JP")
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
            att.place = p
        }
        // 入力欄に残っている未追加のコメントも保存
        let leftover = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !leftover.isEmpty {
            let att = Attachment(context: context)
            att.id = UUID()
            att.createdAt = now
            att.comment = leftover
            att.place = p
        }
        // 写真(プレミアムのみ)
        if store.isPremium {
            for data in pendingImages {
                let att = Attachment(context: context)
                att.id = UUID()
                att.createdAt = now
                att.imageData = data
                att.place = p
            }
        }

        try? context.save()
        dismiss()
    }
}
