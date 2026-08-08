import MapKit
import SwiftUI

/// Swipeable stack of the surviving loops.
struct LoopResultsView: View {
    let loops: [Loop]
    let duration: DurationOption

    @State private var selection: Int = 0

    var body: some View {
        TabView(selection: $selection) {
            ForEach(Array(loops.enumerated()), id: \.element.id) { index, loop in
                LoopMapView(loop: loop).tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: loops.count > 1 ? .always : .never))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .navigationTitle(loops.count == 1 ? "1 loop" : "\(loops.count) loops")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LoopMapView: View {
    let loop: Loop

    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $camera) {
                MapPolyline(coordinates: loop.coordinates)
                    .stroke(.blue, style: StrokeStyle(
                        lineWidth: 4, lineCap: .round, lineJoin: .round))
                if let start = loop.start {
                    Marker("Start", systemImage: "flag.fill", coordinate: start)
                        .tint(.green)
                }
            }
            .onAppear { camera = .rect(Self.boundingRect(for: loop.coordinates)) }

            stats
            driveButton
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var stats: some View {
        HStack {
            stat(String(format: "%.0f", loop.durationMinutes), "min")
            Divider().frame(height: 32)
            stat(String(format: "%.0f", loop.distanceMiles), "mi")
            Divider().frame(height: 32)
            stat(String(format: "%.0f%%", loop.roadStats.highwayPct * 100), "highway")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var driveButton: some View {
        Button("Drive This") {
            if let url = Handoff.googleMapsURL(for: loop) {
                UIApplication.shared.open(url)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.top, 4)
        // Clears the TabView page dots, which draw over the page content.
        .padding(.bottom, 52)
        .background(.bar)
    }

    /// Fit the whole loop with a little breathing room.
    static func boundingRect(for coordinates: [CLLocationCoordinate2D]) -> MKMapRect {
        let rect = coordinates.reduce(MKMapRect.null) { acc, coordinate in
            let point = MKMapPoint(coordinate)
            return acc.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        guard !rect.isNull else { return .world }
        return rect.insetBy(dx: -rect.width * 0.15, dy: -rect.height * 0.15)
    }
}
