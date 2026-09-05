import MapKit
import SwiftUI

/// Swipeable stack of the surviving loops.
struct LoopResultsView: View {
    let loops: [Loop]
    let duration: DurationOption

    @State private var selection: Int = 0

    var body: some View {
        ZStack {
            Theme.background

            TabView(selection: $selection) {
                ForEach(Array(loops.enumerated()), id: \.element.id) { index, loop in
                    LoopMapView(loop: loop).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            if loops.count > 1 {
                VStack {
                    Spacer()
                    dots
                        .padding(.bottom, 10)
                }
            }
        }
        .navigationTitle(loops.count == 1 ? "1 loop" : "\(loops.count) loops")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.backgroundTop, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .preferredColorScheme(.dark)
    }

    /// Hand-rolled rather than the built-in page dots, which draw a grey pill
    /// that fights the warm background.
    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(loops.indices, id: \.self) { i in
                Circle()
                    .fill(i == selection ? Theme.ember : Theme.ink.opacity(0.28))
                    .frame(width: 8, height: 8)
            }
        }
        .animation(.snappy(duration: 0.2), value: selection)
    }
}

struct LoopMapView: View {
    let loop: Loop

    /// Stored, not computed. The polyline runs to thousands of points and this
    /// view re-renders on every swipe of the page stack, so recomputing the
    /// retraced runs in a computed property would redo that work each frame.
    private let retraced: [[CLLocationCoordinate2D]]

    @State private var camera: MapCameraPosition = .automatic

    init(loop: Loop) {
        self.loop = loop
        self.retraced = Geometry.retracedSegments(loop.coordinates)
    }

    var body: some View {
        VStack(spacing: 14) {
            Map(position: $camera) {
                MapPolyline(coordinates: loop.coordinates)
                    .stroke(Theme.ember, style: StrokeStyle(
                        lineWidth: 5, lineCap: .round, lineJoin: .round))

                // Drawn over the base line, wider and in a second colour, so a
                // stretch you cover twice stops reading as one straight line.
                // See HANDOFF.md, "Retrace and reversal, measured 2026-09-04".
                ForEach(Array(retraced.enumerated()), id: \.offset) { _, run in
                    // Same width as the route, not wider: the dashes should mark
                    // the road, not bury it. At 7pt with a round cap they render
                    // as beads fatter than the line underneath.
                    MapPolyline(coordinates: run)
                        .stroke(Theme.repeated, style: StrokeStyle(
                            lineWidth: 5, lineCap: .round, lineJoin: .round,
                            dash: [1, 7]))
                }

                if let start = loop.start {
                    Marker("Start", systemImage: "flag.fill", coordinate: start)
                        .tint(Theme.start)
                }
            }
            .cozyCard()
            .onAppear { camera = .rect(Self.boundingRect(for: loop.coordinates)) }

            stats
            if loop.hasNotableRetrace { retraceNote }
            attribution
            driveButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 34)
    }

    private var stats: some View {
        HStack(spacing: 0) {
            stat(String(format: "%.0f", loop.durationMinutes), "minutes")
            divider
            stat(String(format: "%.0f", loop.distanceMiles), "miles")
            divider
            stat(String(format: "%.0f%%", loop.roadStats.highwayPct * 100), "highway")
            divider
            stat(String(format: "%.0f%%", loop.retracePct), "repeated")
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .cozyCard(radius: 20)
    }

    /// Only shown above the 10% threshold. Below that the doubled stretch is a
    /// corner or a short connector, and a callout would be noise.
    ///
    /// Deliberately explanatory rather than a warning — a repeated stretch is
    /// often unavoidable geometry at the 30-minute size, not a defect. See
    /// SPEC.md, "Known floors".
    private var retraceNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.repeated)
            Text("The dashed stretch is road you cover in both directions.")
                .font(Theme.display(13, .medium))
                .foregroundStyle(Theme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cozyCard(radius: 16)
    }

    /// Required, not decorative, and the wording is not ours to choose. HeiGIT's
    /// terms specify this exact string, and OSM's ODbL separately obliges the
    /// credit. Do not reword it — an earlier version said "Routing ©
    /// OpenRouteService · Map data © OpenStreetMap contributors", which reads
    /// fine and credits both parties but is not what they ask for. Secondary
    /// sources get this wrong too; the terms of service are the only source.
    ///
    /// It lives on this screen because this is the screen where the data is
    /// displayed — the Generate screen shows only an Apple map, which MapKit
    /// credits itself.
    private var attribution: some View {
        Text("© openrouteservice by HeiGIT | Data from OpenStreetMap")
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.inkFaint)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(width: 1, height: 34)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(Theme.display(26, .bold))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
            Text(label)
                .font(Theme.display(12, .medium))
                .foregroundStyle(Theme.inkFaint)
        }
        .frame(maxWidth: .infinity)
    }

    private var driveButton: some View {
        Button {
            if let url = Handoff.googleMapsURL(for: loop) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "car.fill")
                Text("Drive This")
            }
            .font(Theme.display(20, .bold))
            .frame(maxWidth: .infinity, minHeight: 62)
            .foregroundStyle(Theme.onEmber)
            .background(Theme.ember)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
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
