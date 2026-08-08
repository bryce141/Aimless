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

    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        VStack(spacing: 16) {
            Map(position: $camera) {
                MapPolyline(coordinates: loop.coordinates)
                    .stroke(Theme.ember, style: StrokeStyle(
                        lineWidth: 5, lineCap: .round, lineJoin: .round))
                if let start = loop.start {
                    Marker("Start", systemImage: "flag.fill", coordinate: start)
                        .tint(Theme.start)
                }
            }
            .cozyCard()
            .onAppear { camera = .rect(Self.boundingRect(for: loop.coordinates)) }

            stats
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
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .cozyCard(radius: 20)
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
