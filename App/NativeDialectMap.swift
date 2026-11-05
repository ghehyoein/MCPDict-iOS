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
            guard let point = annotation as? PointAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "dialect-dot") ?? MKAnnotationView(annotation: annotation, reuseIdentifier: "dialect-dot")
            view.annotation = annotation
            view.clusteringIdentifier = nil
            view.displayPriority = .required
            view.centerOffset = .zero
            let hex = UInt32(point.point.color.dropFirst(), radix: 16) ?? 0x008080
            let color = UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
            view.image = UIGraphicsImageRenderer(size: CGSize(width: 14, height: 14)).image { _ in
                color.setFill()
                let circle = UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 12, height: 12))
                circle.fill(); UIColor.white.setStroke(); circle.lineWidth = 1.5; circle.stroke()
            }
            view.canShowCallout = true
            view.rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
            return view
        }
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let selected = view.annotation as? PointAnnotation else { return }
            let samePlace = mapView.annotations.compactMap { $0 as? PointAnnotation }.filter {
                $0.coordinate.latitude == selected.coordinate.latitude && $0.coordinate.longitude == selected.coordinate.longitude
            }
            guard samePlace.count > 1 else { return }
            let menu = UIAlertController(title: ui("同一座標的語言點"), message: nil, preferredStyle: .actionSheet)
            for point in samePlace.sorted(by: { $0.point.name < $1.point.name }) {
                menu.addAction(UIAlertAction(title: point.point.name, style: .default) { _ in self.choose(point.point.id) })
            }
            menu.addAction(UIAlertAction(title: ui("取消"), style: .cancel))
            menu.popoverPresentationController?.sourceView = view
            menu.popoverPresentationController?.sourceRect = view.bounds
            mapView.window?.rootViewController?.present(menu, animated: true)
        }
        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
            if let point = view.annotation as? PointAnnotation { choose(point.point.id) }
        }
    }
}
