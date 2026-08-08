import MapKit
import SwiftUI
import UIKit

struct GenerateView: View {
    @State private var location = LocationProvider()
    @State private var model = LoopViewModel()
    @State private var showResults = false

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                map
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.quaternary))

                VStack(spacing: 8) {
                    Text("How long do you want to be out?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Picker("Duration", selection: $model.duration) {
                        ForEach(DurationOption.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Spacer()

                if let message = statusMessage {
                    VStack(spacing: 6) {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        recovery
                    }
                }

                Button(action: generate) {
                    Group {
                        if model.isGenerating {
                            ProgressView().tint(.white)
                        } else {
                            Text("Generate")
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!location.isUsable || model.isGenerating)
            }
            .padding()
            .navigationTitle("Aimless")
            .navigationDestination(isPresented: $showResults) {
                LoopResultsView(loops: model.loops, duration: model.duration)
            }
            .onAppear { location.start() }
            // The fix is taken once. Without this, opening the app in the
            // driveway and generating an hour later somewhere else builds the
            // loop around the driveway.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { location.start() }
            }
        }
    }

    private var map: some View {
        Map(initialPosition: .userLocation(fallback: .automatic)) {
            UserAnnotation()
        }
        .mapControls { MapUserLocationButton() }
    }

    private var statusMessage: String? {
        switch location.status {
        case .denied:
            return "Aimless needs location access to start a loop where you are."
        case .reducedAccuracy:
            return "Precise Location is off, so we can't tell where the loop should start. Turn it on for Aimless."
        case .failed:
            return "Couldn't get a location fix. Somewhere with a clearer view of the sky usually does it."
        case .locating:
            return "Finding you\u{2026}"
        case .ready:
            return model.errorMessage
        }
    }

    /// The way out of each stuck state. Without these the screen states a
    /// problem and offers nothing to do about it.
    @ViewBuilder private var recovery: some View {
        switch location.status {
        case .denied, .reducedAccuracy:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url).font(.footnote)
            }
        case .failed:
            Button("Try Again") { location.start() }.font(.footnote)
        case .locating, .ready:
            EmptyView()
        }
    }

    private func generate() {
        guard let origin = location.current else { return }
        Task {
            await model.generate(from: origin)
            if model.hasResults { showResults = true }
        }
    }
}

#Preview {
    GenerateView()
}
