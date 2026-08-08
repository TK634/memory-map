import Foundation
import Combine
import CoreLocation
import MapKit

/// 「いまここ」記録のための現在地取得
@MainActor
final class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()

    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var isDenied = false
    @Published private(set) var isLocating = false

    private let manager = CLLocationManager()
    private var continuations: [CheckedContinuation<CLLocationCoordinate2D?, Never>] = []

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// 現在地を1回だけ取得(許可がなければ要求)
    func requestCurrentLocation() async -> CLLocationCoordinate2D? {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            isDenied = true
            return nil
        default:
            break
        }
        isLocating = true
        defer { isLocating = false }
        return await withCheckedContinuation { cont in
            continuations.append(cont)
            manager.requestLocation()
        }
    }

    private func resume(with coord: CLLocationCoordinate2D?) {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume(returning: coord) }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        let coord = locations.last?.coordinate
        Task { @MainActor in
            if let coord { self.coordinate = coord }
            self.resume(with: coord)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor in self.resume(with: nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.isDenied = (status == .denied || status == .restricted)
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.requestLocation()
            } else if status == .denied || status == .restricted {
                self.resume(with: nil)
            }
        }
    }
}

/// 現在地の周辺スポットを検索
enum NearbySearch {
    static func spots(around coord: CLLocationCoordinate2D) async -> [MKMapItem] {
        let req = MKLocalPointsOfInterestRequest(center: coord, radius: 400)
        // 日常のおでかけ先になりやすいカテゴリに絞る
        req.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .restaurant, .cafe, .bakery, .brewery, .winery,
            .park, .beach, .nationalPark, .campground, .zoo, .aquarium,
            .museum, .library, .theater, .movieTheater, .amusementPark,
            .store, .foodMarket, .stadium, .fitnessCenter,
            .hotel, .nightlife,
        ])
        guard let resp = try? await MKLocalSearch(request: req).start() else { return [] }
        return Array(resp.mapItems.prefix(12))
    }
}
