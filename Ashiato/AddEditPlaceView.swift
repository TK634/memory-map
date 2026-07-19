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

    @State private var name = ""
    @State private var isJapan = true
    @State private var year: Int = 0
    @State private var visitDate: Date? = nil
    @State private var hasDate = false
    @State private var memo = ""
    @State private var selectedIDs: Set<UUID> = []

    // プレミアム: 写真・コメント
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var pendingImages: [Data] = []      // 圧縮済み。保存時に Attachment 化
    @State private var pendingComments: [String] = []  // 追加予定コメント
    @State private var newComment = ""
    @State private var showPaywall = false

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    /// 既存の添付(タイムライン: 新しい順)
    private var existingAttachments: [Attachment] {
        guard let set = place?.attachments as? Set<Attachment> else { return [] }
        return set.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
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
                        DatePicker("訪問日",
                                   selection: Binding(get: { visitDate ?? Date() },
                                                      set: { visitDate = $0; year = Calendar.current.component(.year, from: $0) }),
                                   displayedComponents: .date)
                    }
                }

                Section("メモ") {
                    TextField("思い出やひとことを", text: $memo, axis: .vertical)
                        .lineLimit(2...4)
                }

                photoCommentSection

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

    // MARK: - 写真・コメント(プレミアム)

    @ViewBuilder
    private var photoCommentSection: some View {
        Section {
            if store.isPremium {
                // 既存の添付タイムライン
                ForEach(existingAttachments, id: \.objectID) { att in
                    attachmentRow(att)
                }
                .onDelete(perform: deleteExistingAttachments)

                // 追加予定の写真
                if !pendingImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
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
                        }
                        .padding(.vertical, 2)
                    }
                }

                PhotosPicker(selection: $photoItems, maxSelectionCount: 5, matching: .images) {
                    Label("写真を追加", systemImage: "photo.on.rectangle.angled")
                }

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
                HStack {
                    TextField("コメントを追加", text: $newComment, axis: .vertical)
                        .lineLimit(1...3)
                    Button("追加") {
                        let t = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        pendingComments.append(t)
                        newComment = ""
                    }
                    .disabled(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                Button { showPaywall = true } label: {
                    HStack {
                        Image(systemName: "lock.fill").foregroundStyle(AppPalette.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("写真とコメントを追加").foregroundStyle(.primary)
                            Text("プレミアムで思い出をもっと残せます")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("写真・コメント")
        }
    }

    private func attachmentRow(_ att: Attachment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if let ui = att.image {
                Image(uiImage: ui).resizable().scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 2) {
                if !att.commentText.isEmpty {
                    Text(att.commentText).font(.subheadline)
                } else if att.image != nil {
                    Text("写真").font(.caption).foregroundStyle(.secondary)
                }
                if let d = att.createdAt {
                    Text(d.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func deleteExistingAttachments(_ offsets: IndexSet) {
        offsets.map { existingAttachments[$0] }.forEach(context.delete)
        try? context.save()
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
            memo = p.memo ?? ""
            selectedIDs = Set(p.visitorIDList)
        } else {
            if members.count == 1, let id = members[0].id { selectedIDs = [id] }
            // 逆ジオコーディングで名前と国内/海外を推定
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
        p.memo = memo.trimmingCharacters(in: .whitespaces)
        p.visitorIDList = Array(selectedIDs)

        // プレミアム: 追加予定の写真・コメントを Attachment 化(念のため課金状態も確認)
        if store.isPremium {
            let now = Date()
            for data in pendingImages {
                let att = Attachment(context: context)
                att.id = UUID()
                att.createdAt = now
                att.imageData = data
                att.place = p
            }
            for text in pendingComments {
                let att = Attachment(context: context)
                att.id = UUID()
                att.createdAt = now
                att.comment = text
                att.place = p
            }
        }

        try? context.save()
        dismiss()
    }
}
