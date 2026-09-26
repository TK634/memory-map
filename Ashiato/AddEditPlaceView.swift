import SwiftUI
import CoreData
import CoreLocation
import PhotosUI
import MapKit

struct AddEditPlaceView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: StoreManager

    let log: TravelLog
    let coordinate: CLLocationCoordinate2D
    let place: Place?          // nil なら新規追加
    let members: [Member]
    var initialName: String = ""   // 検索候補から引き継ぐ場所名
    var initialDate: Date? = nil     // カレンダーで選んだ日

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
    @State private var showDeleteConfirm = false

    /// 保存されていない入力があるか(誤って閉じて消えるのを防ぐ判定)
    private var hasUnsavedInput: Bool {
        !pendingImages.isEmpty
            || !pendingComments.isEmpty
            || !newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    /// 写真を使えるか(自分の課金、または共有相手の課金でも可)
    private var canUsePhotos: Bool {
        store.isPremium || SharedPremium.isActive(log)
    }
    /// 共有相手の課金のおかげで使えている状態か(表示の出し分け用)
    private var isSharedPremium: Bool {
        !store.isPremium && SharedPremium.isActive(log)
    }

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
            ZStack {
                AppStyle.background
                ScrollView {
                    VStack(spacing: 16) {
                        placeHero
                        whoCard
                        whenCard
                        if let place {
                            VStack(alignment: .leading, spacing: 12) {
                                CardTitle(emoji: "🎉", title: "リアクション")
                                ReactionBar(place: place, myName: myMemberName)
                            }
                            .card()
                        }
                        commentCard
                        photoCard
                        if place != nil { deleteButton }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                .defaultScrollAnchor(startsAtBottom ? .bottom : .top)
            }
            .safeAreaInset(edge: .bottom) {
                if place == nil { saveBar }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if place == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            if hasUnsavedInput { showDiscardConfirm = true } else { dismiss() }
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                        }
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完了") { save() }
                            .fontWeight(.bold)
                            .disabled(!canSave)
                    }
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
            .confirmationDialog("この記録を削除しますか?", isPresented: $showDeleteConfirm,
                                titleVisibility: .visible) {
                Button("削除する", role: .destructive) {
                    if let place { context.delete(place); try? context.save() }
                    dismiss()
                }
                Button("やめる", role: .cancel) {}
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

    /// 検証用: 起動引数 -scrollBottom で下端から表示(DEBUGのみ)
    private var startsAtBottom: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-scrollBottom")
        #else
        false
        #endif
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - 場所(地図つきの見出しカード)

    /// 選んでいるメンバーから決まるピンの色(地図のピンと同じルール)
    private var previewPinColor: Color {
        let chosen = members.filter { m in m.id.map(selectedIDs.contains) ?? false }
        if chosen.isEmpty { return AppPalette.none }
        if chosen.count == 1 { return chosen[0].color }
        if members.count > 1 && chosen.count == members.count { return AppPalette.together }
        return AppPalette.partial
    }

    private var placeHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Map(initialPosition: .region(MKCoordinateRegion(center: coordinate,
                                                            latitudinalMeters: 4000,
                                                            longitudinalMeters: 4000)),
                interactionModes: []) {
                Annotation("", coordinate: coordinate) {
                    PinView(color: previewPinColor)
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .frame(height: 150)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 12) {
                IMETextField(text: $name,
                             placeholder: String(localized: "場所の名前"),
                             font: .rounded(26, .black))
                    .frame(height: 34)
                HStack(spacing: 8) {
                    regionChip(emoji: AppRegion.isJapanBased ? "🗾" : "🏠",
                               label: AppRegion.homeLabel, selected: isJapan) { isJapan = true }
                    regionChip(emoji: "✈️", label: AppRegion.abroadLabel, selected: !isJapan) { isJapan = false }
                }
            }
            .padding(18)
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Color(hex: "C98A4B").opacity(0.12), radius: 14, y: 5)
    }

    private func regionChip(emoji: String, label: String, selected: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("\(emoji) \(label)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(selected ? .white : AppPalette.chrome.opacity(0.7))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(selected ? AnyShapeStyle(AppStyle.accentGradient)
                                     : AnyShapeStyle(Color.gray.opacity(0.10)),
                            in: Capsule())
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - だれと

    private var whoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(emoji: "👫", title: "だれと行った?")
            if members.isEmpty {
                Text("メンバー画面から登録してください")
                    .font(.caption).foregroundStyle(.secondary)
            }
            FlowRow(spacing: 8) {
                ForEach(members, id: \.objectID) { m in
                    if let id = m.id { memberChip(m, id: id) }
                }
            }
        }
        .card()
    }

    private func memberChip(_ m: Member, id: UUID) -> some View {
        let on = selectedIDs.contains(id)
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                if on { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
            }
        } label: {
            HStack(spacing: 8) {
                MemberAvatar(name: m.displayName, color: on ? m.color : .gray.opacity(0.45), size: 28)
                Text(m.displayName)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(on ? AppPalette.chrome : .secondary)
                if on {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(m.color)
                }
            }
            .padding(.leading, 5).padding(.trailing, 14).padding(.vertical, 5)
            .background(on ? m.color.opacity(0.14) : Color.gray.opacity(0.07), in: Capsule())
            .overlay(Capsule().stroke(on ? m.color : .clear, lineWidth: 2))
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - いつ

    private var nightsText: String? {
        guard hasDate, hasEndDate, let s = visitDate, let e = visitEndDate, e > s else { return nil }
        let nights = Calendar.current.dateComponents([.day], from: s, to: e).day ?? 0
        return "\(nights)泊\(nights + 1)日"
    }

    private var whenCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(emoji: "📅", title: "いつ?",
                      trailing: nightsText.map { t in
                          AnyView(Text(t)
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(AppStyle.accentGradient, in: Capsule()))
                      })
            if hasDate {
                HStack(spacing: 8) {
                    tripChip("☀️ 日帰り", selected: !hasEndDate) { hasEndDate = false }
                    tripChip("🌙 泊まり", selected: hasEndDate) {
                        hasEndDate = true
                        if let s = visitDate, (visitEndDate ?? s) <= s {
                            visitEndDate = Calendar.current.date(byAdding: .day, value: 1, to: s)
                        }
                    }
                }
                dateRow(icon: "figure.walk.departure", label: "行った日",
                        selection: Binding(get: { visitDate ?? Date() },
                                           set: { visitDate = $0
                                                  year = Calendar.current.component(.year, from: $0)
                                                  if let e = visitEndDate, e < $0 { visitEndDate = $0 } }),
                        from: nil)
                if hasEndDate {
                    dateRow(icon: "house.fill", label: "帰った日",
                            selection: Binding(get: { visitEndDate ?? visitDate ?? Date() },
                                               set: { visitEndDate = $0 }),
                            from: visitDate ?? Date())
                }
                Button {
                    withAnimation { hasDate = false; hasEndDate = false }
                } label: {
                    Text("日付はわからない(年だけにする)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                HStack {
                    Text("年")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppPalette.chrome)
                    Spacer()
                    Menu {
                        Picker("", selection: $year) {
                            Text("未設定").tag(0)
                            ForEach((1975...currentYear).reversed(), id: \.self) { y in
                                Text("\(String(y))年").tag(y)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(year == 0 ? String(localized: "未設定") : "\(String(year))年")
                            Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                        }
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppPalette.accent)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(AppPalette.accent.opacity(0.12), in: Capsule())
                    }
                }
                Button {
                    withAnimation {
                        hasDate = true
                        if visitDate == nil {
                            let cal = Calendar.current
                            visitDate = (year > 0 && year != currentYear)
                                ? cal.date(from: DateComponents(year: year, month: 1, day: 1))
                                : Date()
                        }
                    }
                } label: {
                    Label("日付を入れる", systemImage: "plus")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(AppPalette.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }

    private func tripChip(_ label: LocalizedStringKey, selected: Bool,
                          action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { action() }
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(selected ? .white : AppPalette.chrome.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selected ? AnyShapeStyle(AppStyle.accentGradient)
                                     : AnyShapeStyle(Color.gray.opacity(0.10)),
                            in: Capsule())
        }
        .buttonStyle(PressableStyle())
    }

    private func dateRow(icon: String, label: LocalizedStringKey,
                         selection: Binding<Date>, from: Date?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppPalette.accent)
                .frame(width: 30, height: 30)
                .background(AppPalette.accent.opacity(0.12), in: Circle())
            Text(label)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(AppPalette.chrome)
            Spacer()
            if let from {
                DatePicker("", selection: selection, in: from..., displayedComponents: .date)
                    .labelsHidden()
            } else {
                DatePicker("", selection: selection, displayedComponents: .date)
                    .labelsHidden()
            }
        }
        .padding(10)
        .background(Color(hex: "FFF6EA"), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 保存・削除

    /// 新規登録のときだけ出る大きな保存ボタン
    private var saveBar: some View {
        Button { save() } label: {
            Label("あしあとを残す", systemImage: "shoeprints.fill")
        }
        .buttonStyle(PrimaryButtonStyle(enabled: canSave))
        .disabled(!canSave)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(
            LinearGradient(colors: [Color(hex: "FFFAF4").opacity(0), Color(hex: "FFFAF4")],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        )
    }

    private var deleteButton: some View {
        Button { showDeleteConfirm = true } label: {
            Label("この記録を削除", systemImage: "trash")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Color.red.opacity(0.75))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
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

    // MARK: - ひとこと(無料)

    /// 名前からメンバーの色を引く(コメントのアイコン用)
    private func color(forAuthor name: String?) -> Color {
        guard let name else { return AppPalette.accent }
        return members.first { $0.displayName == name }?.color ?? AppPalette.accent
    }

    private var commentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTitle(emoji: "💬", title: "ひとこと")
            // 古い順に並べて、下の入力欄へ会話のようにつながる
            ForEach(existingComments.reversed(), id: \.objectID) { att in
                commentBubble(author: att.authorName, text: att.commentText, date: att.createdAt)
                    .contextMenu {
                        Button(role: .destructive) {
                            context.delete(att)
                            try? context.save()
                        } label: { Label("削除", systemImage: "trash") }
                    }
            }
            ForEach(Array(pendingComments.enumerated()), id: \.offset) { i, text in
                commentBubble(author: myMemberName, text: text, date: nil)
                    .contextMenu {
                        Button(role: .destructive) { pendingComments.remove(at: i) } label: {
                            Label("削除", systemImage: "trash")
                        }
                    }
            }
            HStack(alignment: .bottom, spacing: 8) {
                IMETextField(text: $newComment,
                             placeholder: String(localized: "思い出をひとこと…"),
                             font: .rounded(15, .regular),
                             returnKey: .send,
                             onCommit: sendComment)
                    .frame(height: 22)
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(Color.gray.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                Button(action: sendComment) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(commentIsEmpty ? AnyShapeStyle(Color.gray.opacity(0.3))
                                                   : AnyShapeStyle(AppStyle.accentGradient),
                                    in: Circle())
                }
                .buttonStyle(PressableStyle())
                .disabled(commentIsEmpty)
            }
        }
        .card()
    }

    private var commentIsEmpty: Bool {
        newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendComment() {
        let t = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            pendingComments.append(t)
            newComment = ""
        }
        // 既存の記録なら即反映(保存ボタン不要)
        if place != nil { commitPendingAttachments() }
    }

    private func commentBubble(author: String?, text: String, date: Date?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if let author, !author.isEmpty {
                MemberAvatar(name: author, color: color(forAuthor: author), size: 30)
            } else {
                // 投稿者が記録されていない古いコメント
                Image(systemName: "person.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.gray.opacity(0.35), in: Circle())
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let author, !author.isEmpty {
                        Text(author)
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppPalette.chrome)
                    }
                    if let date {
                        Text(date.jaDateText)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(text)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(AppPalette.chrome)
                    .padding(.horizontal, 13).padding(.vertical, 9)
                    .background(Color(hex: "FFF1DF"),
                                in: UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 18,
                                                           bottomTrailingRadius: 18, topTrailingRadius: 18,
                                                           style: .continuous))
            }
            Spacer(minLength: 0)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - 写真(プレミアム)

    @ViewBuilder
    private var photoCard: some View {
        if canUsePhotos {
            VStack(alignment: .leading, spacing: 12) {
                CardTitle(emoji: "📸", title: "写真", trailing: AnyView(HStack(spacing: 8) {
                    if isSharedPremium {
                        Label("共有プレミアム", systemImage: "person.2.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppPalette.accent)
                    }
                    if !allPhotoImages.isEmpty {
                        Text("\(allPhotoImages.count)枚")
                            .font(.caption.bold()).foregroundStyle(.secondary)
                    }
                }))

                if importingCount > 0 {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("写真を読み込み中… \(importedCount)/\(importingCount)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color(hex: "FFF6EA"), in: RoundedRectangle(cornerRadius: 16))
                }

                if allPhotoImages.isEmpty && importingCount == 0 {
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .images) {
                        VStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(AppStyle.accentGradient, in: Circle())
                            Text("写真を追加")
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundStyle(AppPalette.chrome)
                            Text("この場所の思い出を残そう")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 26)
                        .background(Color(hex: "FFF6EA"),
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(AppPalette.accent.opacity(0.35),
                                              style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                        )
                    }
                } else {
                    photoGrid
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .images) {
                        Label("写真を追加", systemImage: "plus")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(AppPalette.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(AppPalette.accent.opacity(0.1), in: Capsule())
                    }
                }
            }
            .card()
        } else {
            Button { showPaywall = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(AppStyle.accentGradient,
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("📸 写真を残す")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppPalette.chrome)
                        Text("プレミアムで思い出の写真を無制限に")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                }
                .card(padding: 14)
            }
            .buttonStyle(PressableStyle())
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
        if canUsePhotos {
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
            // カレンダーで選んだ日を「行った日」に
            if let d = initialDate {
                hasDate = true
                visitDate = d
                year = Calendar.current.component(.year, from: d)
            }
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
        if canUsePhotos {
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
