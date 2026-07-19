import SwiftUI
import CoreData

// MARK: - 色ユーティリティ

extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: .alphanumerics.inverted)
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        let v = UInt64(h, radix: 16) ?? 0x999999
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}

enum AppPalette {
    static let memberColors = ["D64550", "3A7CA5", "5B9A6B", "B07AA1", "E8963E", "7A6ADB", "C9803A", "3FA3A3"]
    static let together = Color(hex: "2FA98C")
    static let partial  = Color(hex: "8A7CB0")
    static let none     = Color(hex: "9AA7AB")
    static let accent   = Color(hex: "E8963E")
    static let chrome   = Color(hex: "16323B")
}

// MARK: - Member / Place の便利プロパティ

extension Member {
    var displayName: String { name ?? "?" }
    var color: Color { Color(hex: colorHex ?? "9AA7AB") }
}

extension Place {
    /// visitorIDs はメンバーUUIDのカンマ区切り文字列
    var visitorIDList: [UUID] {
        get { (visitorIDs ?? "").split(separator: ",").compactMap { UUID(uuidString: String($0)) } }
        set { visitorIDs = newValue.map(\.uuidString).joined(separator: ",") }
    }

    func visitors(in members: [Member]) -> [Member] {
        let ids = Set(visitorIDList)
        return members.filter { m in m.id.map(ids.contains) ?? false }
    }

    func pinColor(members: [Member]) -> Color {
        let vs = visitors(in: members)
        if vs.isEmpty { return AppPalette.none }
        if vs.count == 1 { return vs[0].color }
        if members.count > 1 && vs.count == members.count { return AppPalette.together }
        return AppPalette.partial
    }

    func whoLabel(members: [Member]) -> String {
        let vs = visitors(in: members)
        if vs.isEmpty { return "未設定" }
        if members.count > 1 && vs.count == members.count { return "全員一緒" }
        return vs.map(\.displayName).joined(separator: "・")
    }
}

// MARK: - フィルター

enum RegionFilter: String, CaseIterable, Identifiable {
    case all, jp, ov
    var id: String { rawValue }
    var label: String { self == .all ? "すべて" : (self == .jp ? "国内" : "海外") }
}

enum WhoFilter: Hashable {
    case all
    case member(UUID)
    case together
}

struct PlaceFilter {
    var who: WhoFilter = .all
    var whoOnly: Bool = false          // 「〜だけ」トグル
    var region: RegionFilter = .all
    var year: Int? = nil               // nil = すべての年, 0 = 年未設定

    func matches(_ p: Place, members: [Member]) -> Bool {
        if region == .jp && !p.isJapan { return false }
        if region == .ov && p.isJapan { return false }
        if let y = year {
            if y == 0 { if p.year != 0 { return false } }
            else if p.year != Int16(y) { return false }
        }
        switch who {
        case .all:
            return true
        case .together:
            let ids = Set(p.visitorIDList)
            return members.count > 1 && members.allSatisfy { m in m.id.map(ids.contains) ?? false }
        case .member(let id):
            let vs = p.visitors(in: members)
            guard vs.contains(where: { $0.id == id }) else { return false }
            if whoOnly && vs.count != 1 { return false }
            return true
        }
    }
}
