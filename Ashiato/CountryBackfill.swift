import Foundation
import CoreData
import CoreLocation

/// 国コードが入っていない古い記録に、あとから国コードを補う。
/// 国内の記録は住所を調べなくても居住国のコードで決まる。
/// 海外の記録は位置から住所を調べる(調べすぎると制限がかかるので1件ずつ間をあける)。
@MainActor
enum CountryBackfill {
    private static var running = false

    static func run(context: NSManagedObjectContext) async {
        guard !running else { return }
        running = true
        defer { running = false }

        let req = NSFetchRequest<Place>(entityName: "Place")
        req.predicate = NSPredicate(format: "countryCode == nil OR countryCode == %@", "")
        guard let places = try? context.fetch(req), !places.isEmpty else { return }

        let geocoder = CLGeocoder()
        var changed = false
        for p in places {
            if p.isJapan {
                p.countryCode = AppRegion.homeISOCode
                changed = true
                continue
            }
            let loc = CLLocation(latitude: p.latitude, longitude: p.longitude)
            if let code = try? await geocoder.reverseGeocodeLocation(loc).first?.isoCountryCode {
                p.countryCode = code
                changed = true
            }
            try? await Task.sleep(for: .milliseconds(1200))
        }
        if changed { try? context.save() }
    }
}
