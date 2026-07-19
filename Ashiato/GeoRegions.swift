import Foundation
import MapKit
import SwiftUI

/// アニメ調フラット地図用の塗り分け領域(国・都道府県)
struct GeoRegion: Identifiable {
    let id: String
    let color: Color
    let polygons: [[CLLocationCoordinate2D]]
}

enum GeoData {

    /// アニメ調パステルパレット(隣り合う領域で色が変わるよう順番に割当)
    static let pastel = [
        "FFC2B4", "FFDCAB", "FFF2B0", "C8E8B0", "AFE6D6",
        "B0D8F2", "CFC0F0", "F2C0DC", "E8D8B8", "B8E0E8",
    ]

    /// 海の色(フラットな青)
    static let ocean = Color(hex: "7EC4EA")

    /// 海を覆う帯状ポリゴン(巨大1枚だと描画が乱れるため経度90度ずつに分割)
    static var oceanBands: [[CLLocationCoordinate2D]] {
        stride(from: -180.0, to: 180.0, by: 90.0).map { lon in
            [
                CLLocationCoordinate2D(latitude: 85, longitude: lon + 0.01),
                CLLocationCoordinate2D(latitude: 85, longitude: lon + 90 - 0.01),
                CLLocationCoordinate2D(latitude: -85, longitude: lon + 90 - 0.01),
                CLLocationCoordinate2D(latitude: -85, longitude: lon + 0.01),
            ]
        }
    }

    /// バンドルの GeoJSON を読み込んで色付き領域に変換
    static func load(_ resource: String) -> [GeoRegion] {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "geojson"),
              let data = try? Data(contentsOf: url),
              let objects = try? MKGeoJSONDecoder().decode(data) else { return [] }

        var regions: [GeoRegion] = []
        var index = 0
        for object in objects {
            guard let feature = object as? MKGeoJSONFeature else { continue }
            var name = "\(resource)-\(index)"
            if let pd = feature.properties,
               let dict = try? JSONSerialization.jsonObject(with: pd) as? [String: Any],
               let n = dict["name"] as? String {
                name = n
            }
            var polys: [[CLLocationCoordinate2D]] = []
            for geom in feature.geometry {
                if let poly = geom as? MKPolygon {
                    polys.append(poly.coordinateList)
                } else if let multi = geom as? MKMultiPolygon {
                    for p in multi.polygons { polys.append(p.coordinateList) }
                }
            }
            guard !polys.isEmpty else { continue }
            let hex = pastel[index % pastel.count]
            regions.append(GeoRegion(id: name, color: Color(hex: hex), polygons: polys))
            index += 1
        }
        return regions
    }
}

extension MKPolygon {
    var coordinateList: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
