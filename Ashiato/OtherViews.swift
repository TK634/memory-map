import SwiftUI
import CoreData
import CloudKit
import UIKit

// MARK: - メンバー管理

struct MembersView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    let log: TravelLog

    @FetchRequest(sortDescriptors: [SortDescriptor(\Member.createdAt)])
    private var members: FetchedResults<Member>

    var body: some View {
        NavigationStack {
            List {
                Section(footer: Text("この記録は共有ボタンから招待した相手と一緒に見られます。")) {
                    ForEach(members, id: \.objectID) { m in
                        MemberRow(member: m)
                    }
                    .onDelete { idx in
                        idx.map { members[$0] }.forEach { m in
                            // 削除するメンバーを各記録から外す
                            if let id = m.id {
                                let req = NSFetchRequest<Place>(entityName: "Place")
                                let all = (try? context.fetch(req)) ?? []
                                all.forEach { p in p.visitorIDList.removeAll { $0 == id } }
                            }
                            context.delete(m)
                        }
                        try? context.save()
                    }
                }
                Button {
                    let m = Member(context: context)
                    m.id = UUID()
                    m.createdAt = Date()
                    m.name = "メンバー\(members.count + 1)"
                    let used = Set(members.compactMap(\.colorHex))
                    m.colorHex = AppPalette.memberColors.first { !used.contains($0) }
                        ?? AppPalette.memberColors[members.count % AppPalette.memberColors.count]
                    m.log = log
                    try? context.save()
                } label: {
                    Label("メンバーを追加", systemImage: "plus")
                }
            }
            .navigationTitle("メンバー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } } }
        }
    }
}

struct MemberRow: View {
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var member: Member
    @State private var showPalette = false

    var body: some View {
        HStack {
            Button { showPalette.toggle() } label: {
                RoundedRectangle(cornerRadius: 6).fill(member.color).frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            TextField("名前", text: Binding(
                get: { member.name ?? "" },
                set: { member.name = $0 }))
                .onSubmit { try? context.save() }
        }
        .popover(isPresented: $showPalette) {
            HStack(spacing: 8) {
                ForEach(AppPalette.memberColors, id: \.self) { hex in
                    Button {
                        member.colorHex = hex
                        try? context.save()
                        showPalette = false
                    } label: {
                        RoundedRectangle(cornerRadius: 6).fill(Color(hex: hex)).frame(width: 26, height: 26)
                    }
                }
            }
            .padding()
            .presentationCompactAdaptation(.popover)
        }
    }
}

// MARK: - ランキング

struct RankingView: View {
    @Environment(\.dismiss) private var dismiss
    let places: [Place]
    let members: [Member]
    let filter: PlaceFilter

    private struct Row: Identifiable {
        let id = UUID()
        let member: Member
        let count: Int
        let jp: Int
        var ov: Int { count - jp }
    }

    private var scoped: [Place] {
        // 年・区分フィルターのみ反映(誰フィルターは無視)
        var f = filter; f.who = .all; f.whoOnly = false
        return places.filter { f.matches($0, members: members) }
    }

    private var rows: [Row] {
        members.map { m in
            let mine = scoped.filter { p in m.id.map { p.visitorIDList.contains($0) } ?? false }
            return Row(member: m, count: mine.count, jp: mine.filter(\.isJapan).count)
        }
        .sorted { $0.count > $1.count }
    }

    private var scopeLabel: String {
        var parts: [String] = []
        if let y = filter.year { parts.append(y == 0 ? "年未設定" : "\(String(y))年") }
        if filter.region != .all { parts.append(filter.region.label) }
        return "対象:" + (parts.isEmpty ? "すべての記録" : parts.joined(separator: "・")) + "(\(scoped.count)件)"
    }

    var body: some View {
        NavigationStack {
            List {
                Section(footer: Text(scopeLabel)) {
                    let maxCount = max(1, rows.map(\.count).max() ?? 1)
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                        HStack(spacing: 12) {
                            Text("\(i + 1)")
                                .font(.headline)
                                .foregroundStyle(i == 0 && r.count > 0 ? AppPalette.accent : .secondary)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Circle().fill(r.member.color).frame(width: 10, height: 10)
                                    Text(r.member.displayName).font(.subheadline.bold())
                                    Spacer()
                                    Text("\(r.count)件").font(.subheadline.bold())
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color(.systemGray5))
                                        Capsule().fill(r.member.color)
                                            .frame(width: geo.size.width * CGFloat(r.count) / CGFloat(maxCount))
                                    }
                                }
                                .frame(height: 8)
                                Text("国内 \(r.jp) ・ 海外 \(r.ov)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("訪問数ランキング")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
        }
    }
}

// MARK: - 一覧

struct PlacesListView: View {
    @Environment(\.dismiss) private var dismiss
    let places: [Place]
    let members: [Member]
    let onSelect: (Place) -> Void

    private var sorted: [Place] {
        places.sorted {
            if $0.year != $1.year { return $0.year > $1.year }
            return ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
        }
    }

    var body: some View {
        NavigationStack {
            List(sorted, id: \.objectID) { p in
                Button { onSelect(p) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(p.pinColor(members: members))
                            .frame(width: 12, height: 12).padding(.top, 4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name ?? "").font(.subheadline.bold()).foregroundStyle(.primary)
                            HStack(spacing: 6) {
                                Text(p.whoLabel(members: members))
                                Text(p.isJapan ? "国内" : "海外")
                                if p.year > 0 { Text("\(String(p.year))年") }
                            }
                            .font(.caption2).foregroundStyle(.secondary)
                            if let snippet = p.snippetText {
                                Text(snippet).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            }
            .overlay {
                if places.isEmpty {
                    ContentUnavailableView("記録がありません", systemImage: "mappin.slash",
                                           description: Text("地図をタップして最初の一か所を追加しましょう"))
                }
            }
            .navigationTitle("訪問地(\(places.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
        }
    }
}

// MARK: - iCloud共有シート

struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let vc = UICloudSharingController(share: share, container: container)
        vc.availablePermissions = [.allowReadWrite, .allowPrivate]
        return vc
    }
    func updateUIViewController(_ vc: UICloudSharingController, context: Context) {}
}
