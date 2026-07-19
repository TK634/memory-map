import SwiftUI
import CoreData
import CoreLocation

struct AddEditPlaceView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

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

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }

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
        }
    }

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
        try? context.save()
        dismiss()
    }
}
