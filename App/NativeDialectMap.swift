import SwiftUI
import MapKit

struct NativeDialectMap: UIViewRepresentable {
    let points: [DialectPoint]
    let fit: Int
    let choose: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(choose: choose) }
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 34, longitude: 108), span: MKCoordinateSpan(latitudeDelta: 38, longitudeDelta: 48)), animated: false)
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.choose = choose
        context.coordinator.update(map, points: points, fit: fit)
    }
    final class PointAnnotation: NSObject, MKAnnotation {
        let point: DialectPoint
        var coordinate: CLLocationCoordinate2D { .init(latitude: point.latitude, longitude: point.longitude) }
        var title: String? { point.name }
        var subtitle: String? { point.reading }
        init(_ point: DialectPoint) { self.point = point }
    }
    final class Coordinator: NSObject, MKMapViewDelegate {
        var points = [DialectPoint]()
        var fit = 0
        var choose: (String) -> Void
        init(choose: @escaping (String) -> Void) { self.choose = choose }
        func update(_ map: MKMapView, points: [DialectPoint], fit: Int) {
            if self.points != points {
                self.points = points
                map.removeAnnotations(map.annotations)
                map.addAnnotations(points.map(PointAnnotation.init))
            }
            if self.fit != fit {
                self.fit = fit
                if !map.annotations.isEmpty { map.showAnnotations(map.annotations, animated: true) }
            }
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: "dialect") as? MKMarkerAnnotationView) ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "dialect")
            view.annotation = annotation
            if let point = annotation as? PointAnnotation {
                view.clusteringIdentifier = "dialects"
                let hex = UInt32(point.point.color.dropFirst(), radix: 16) ?? 0x008080
                view.markerTintColor = UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
                view.glyphText = nil
                view.canShowCallout = true
                view.rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
            } else if let cluster = annotation as? MKClusterAnnotation {
                view.clusteringIdentifier = nil
                view.markerTintColor = .systemTeal
                view.glyphText = String(cluster.memberAnnotations.count)
                view.canShowCallout = false
                view.rightCalloutAccessoryView = nil
            } else { return nil }
            return view
        }
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let cluster = view.annotation as? MKClusterAnnotation {
                let unique = Set(cluster.memberAnnotations.map { "\($0.coordinate.longitude),\($0.coordinate.latitude)" })
                if unique.count > 1 { mapView.showAnnotations(cluster.memberAnnotations, animated: true) }
                else {
                    // Overlapping source coordinates are not displaced or discarded.
                    let menu = UIAlertController(title: "同一座標的字表", message: nil, preferredStyle: .actionSheet)
                    for annotation in cluster.memberAnnotations.compactMap({ $0 as? PointAnnotation }) {
                        menu.addAction(UIAlertAction(title: annotation.point.name, style: .default) { _ in self.choose(annotation.point.id) })
                    }
                    menu.addAction(UIAlertAction(title: "取消", style: .cancel))
                    menu.popoverPresentationController?.sourceView = view
                    menu.popoverPresentationController?.sourceRect = view.bounds
                    mapView.window?.rootViewController?.present(menu, animated: true)
                }
            }
        }
        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
            if let point = view.annotation as? PointAnnotation { choose(point.point.id) }
        }
    }
}
