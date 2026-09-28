import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore
import Foundation
#if canImport(MapKit)
import MapKit
#endif

// MARK: - Route map (#524)
//
// A MapKit map of the captured route polyline, drawn with start (green) + end (red) markers and the line in
// Effort's Exercise green — the Apple analogue of Android's `RouteCanvas`, but on real map tiles. On the
// workout page it is a still preview (a map that pans inside a scroll view fights the scroll), and a tap
// opens it full size, as Fitness does. Built as a platform-bridged representable
// around `MKMapView` so it runs on BOTH iOS 17 and macOS 13 (SwiftUI's newer `Map { MapPolyline }` needs
// iOS 17 / macOS 14, and the macOS deployment target is 13). The map is offline-capable: MapKit caches
// tiles locally and the route itself is on-device — NOOP never sends the route anywhere.

#if canImport(MapKit) && canImport(UIKit)
import UIKit
typealias RouteMapRepresentable = UIViewRepresentable
#elseif canImport(MapKit) && canImport(AppKit)
import AppKit
typealias RouteMapRepresentable = NSViewRepresentable
#endif

#if canImport(MapKit)
struct WorkoutRouteMap: RouteMapRepresentable {
    let points: [RouteMath.LatLng]
    /// False for the preview on the workout page: no panning or zooming, the tap belongs to the page.
    var interactive = true

    private var coordinates: [CLLocationCoordinate2D] {
        points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func makeMap(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsUserLocation = false
        map.isScrollEnabled = interactive
        map.isZoomEnabled = interactive
        #if canImport(UIKit)
        map.isUserInteractionEnabled = interactive
        #endif
        configure(map)
        return map
    }

    /// Draw the polyline + start/end pins and frame the route. Replaces any existing overlays so a
    /// re-render doesn't stack them.
    private func configure(_ map: MKMapView) {
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations)
        let coords = coordinates
        guard coords.count >= 2 else { return }
        let line = MKPolyline(coordinates: coords, count: coords.count)
        map.addOverlay(line)

        let start = RouteEndpoint(isStart: true); start.coordinate = coords.first!; start.title = String(localized: "Start")
        let end = RouteEndpoint(isStart: false); end.coordinate = coords.last!; end.title = String(localized: "Finish")
        map.addAnnotations([start, end])

        // Frame the whole route with a little padding so the line isn't flush to the edges.
        let rect = line.boundingMapRect
        let inset = UIEdgeInsetsLikePadding
        map.setVisibleMapRect(rect, edgePadding: inset, animated: false)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKPolylineRenderer(polyline: line)
            // Effort's colour, the Exercise green every other workout figure uses.
            r.strokeColor = RoutePlatformColor.effort
            r.lineWidth = 4
            r.lineJoin = .round
            r.lineCap = .round
            return r
        }

        /// Start green, finish red: the system colours Fitness marks a route's ends in.
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let endpoint = annotation as? RouteEndpoint else { return nil }
            let id = endpoint.isStart ? "start" : "finish"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: endpoint, reuseIdentifier: id)
            view.annotation = endpoint
            view.markerTintColor = endpoint.isStart ? RoutePlatformColor.start : RoutePlatformColor.finish
            view.glyphImage = nil
            return view
        }
    }

    #if canImport(UIKit)
    private var UIEdgeInsetsLikePadding: UIEdgeInsets { UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24) }
    func makeUIView(context: Context) -> MKMapView { makeMap(context: context) }
    func updateUIView(_ map: MKMapView, context: Context) { configure(map) }
    #elseif canImport(AppKit)
    private var UIEdgeInsetsLikePadding: NSEdgeInsets { NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24) }
    func makeNSView(context: Context) -> MKMapView { makeMap(context: context) }
    func updateNSView(_ map: MKMapView, context: Context) { configure(map) }
    #endif
}

/// One end of the route, so its marker can be told apart from the other.
private final class RouteEndpoint: MKPointAnnotation {
    let isStart: Bool
    init(isStart: Bool) {
        self.isStart = isStart
        super.init()
    }
}

/// The route's colours as platform colours (MapKit's renderer and markers can't take a SwiftUI `Color`):
/// the line in the Effort token, the ends in the system green and red.
private enum RoutePlatformColor {
    #if canImport(UIKit)
    static let effort = UIColor(StrandPalette.activityExerciseText)
    static let start = UIColor.systemGreen
    static let finish = UIColor.systemRed
    #elseif canImport(AppKit)
    static let effort = NSColor(StrandPalette.activityExerciseText)
    static let start = NSColor.systemGreen
    static let finish = NSColor.systemRed
    #endif
}
#else
/// Platforms without MapKit (none we ship, but keeps the type resolvable): no route map.
struct WorkoutRouteMap: View {
    let points: [RouteMath.LatLng]
    var interactive = true
    var body: some View { Color.clear }
}
#endif

/// The route full size, opened from the preview on the workout page: pan and zoom, ✕ to close.
struct WorkoutRouteMapSheet: View {
    let points: [RouteMath.LatLng]
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WorkoutRouteMap(points: points)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(Text(title))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { SheetCloseButton { dismiss() } }
                }
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 560)
        #endif
    }
}

#if DEBUG
#Preview("Workout Detail") {
    NavigationStack {
        WorkoutDetailView(row: WorkoutRow(
            startTs: Int(Date().timeIntervalSince1970) - 3600,
            endTs: Int(Date().timeIntervalSince1970),
            sport: "Running", source: "whoop", durationS: 3600, energyKcal: 712,
            avgHr: 152, maxHr: 178, strain: 14.2, distanceM: 10_400,
            zonesJSON: #"{"z1":12.5,"z2":28.0,"z3":33.5,"z4":18.0,"z5":6.0}"#, notes: nil, steps: nil))
            .environmentObject(Repository(deviceId: "preview"))
    }
    .frame(width: 1040, height: 940)
    .preferredColorScheme(.dark)
}
#endif
