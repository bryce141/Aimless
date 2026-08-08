import MapKit
import SwiftUI

struct GenerateView: View {
    @State private var location = LocationProvider()
    @State private var model = LoopViewModel()
    @State private var showResults = false

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
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
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
                .disabled(location.current == nil || model.isGenerating)
            }
            .padding()
            .navigationTitle("Aimless")
            .navigationDestination(isPresented: $showResults) {
                LoopResultsView(loops: model.loops, duration: model.duration)
            }
            .onAppear { location.start() }
        }
    }

    private var map: some View {
        Map(initialPosition: .userLocation(fallback: .automatic)) {
            UserAnnotation()
        }
        .mapControls { MapUserLocationButton() }
    }

    private var statusMessage: String? {
        if location.isDenied {
            return "Aimless needs location access to start a loop where you are. Enable it in Settings."
        }
        if location.current == nil {
            return "Finding you\u{2026}"
        }
        return model.errorMessage
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
