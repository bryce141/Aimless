import MapKit
import SwiftUI
import UIKit

struct GenerateView: View {
    @State private var location = LocationProvider()
    @State private var model = LoopViewModel()
    @State private var showResults = false

    @Environment(\.scenePhase) private var scenePhase

    #if DEBUG
    /// Screenshot automation. Launching with `-autoGenerate` taps Generate for
    /// us as soon as a fix arrives.
    ///
    /// This exists because there is no way to drive the simulator from a script
    /// otherwise: `simctl` has no tap command, and synthesising a click through
    /// System Events needs an accessibility grant a build machine won't have.
    /// DEBUG-only, so it cannot reach a release build.
    @State private var didAutoGenerate = false
    private var wantsAutoGenerate: Bool {
        ProcessInfo.processInfo.arguments.contains("-autoGenerate")
    }
    #endif

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background

                // Map and picker read as one block — "here, and for this long" —
                // with the action pinned to the bottom. Two spacers instead of
                // one would center the picker in the leftover space and open a
                // dead gap under the map.
                // The map takes the slack rather than a Spacer, so leftover
                // space on a big phone becomes more map instead of a void above
                // the button. Controls stay pinned to the bottom where a thumb
                // already is.
                VStack(spacing: 0) {
                    header
                    map
                        .frame(minHeight: 240, maxHeight: .infinity)
                        .cozyCard()
                        .padding(.top, 18)

                    durationPicker
                        .padding(.top, 16)

                    status
                        .padding(.top, 14)
                    generateButton
                        .padding(.top, 14)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            .toolbar(.hidden, for: .navigationBar)
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
            #if DEBUG
            .onChange(of: location.isUsable) { _, usable in
                guard usable, wantsAutoGenerate, !didAutoGenerate else { return }
                didAutoGenerate = true
                generate()
            }
            #endif
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("Aimless")
                .font(Theme.display(38, .bold))
                .foregroundStyle(Theme.ink)
            Text("No particular place to be")
                .font(Theme.display(15, .medium))
                .foregroundStyle(Theme.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .padding(.top, 8)
    }

    private var map: some View {
        Map(initialPosition: .userLocation(fallback: .automatic)) {
            UserAnnotation()
        }
        .mapControls { MapUserLocationButton() }
    }

    // MARK: - Duration

    /// A slider over three discrete stops rather than a segmented control.
    /// `model.duration` stays the single source of truth; this projects it onto
    /// an index so there's no second piece of state to drift.
    private var durationIndex: Binding<Double> {
        Binding(
            get: {
                Double(DurationOption.allCases.firstIndex(of: model.duration) ?? 0)
            },
            set: { raw in
                let i = min(max(Int(raw.rounded()), 0), DurationOption.allCases.count - 1)
                model.duration = DurationOption.allCases[i]
            }
        )
    }

    private var durationPicker: some View {
        VStack(spacing: 14) {
            Text("How long do you want to be out?")
                .font(Theme.display(15, .medium))
                .foregroundStyle(Theme.inkSoft)

            Text(model.duration.spokenLabel)
                .font(Theme.display(46, .bold))
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.25), value: model.duration)

            VStack(spacing: 6) {
                Slider(
                    value: durationIndex,
                    in: 0...Double(DurationOption.allCases.count - 1),
                    step: 1
                )
                .tint(Theme.ember)

                HStack {
                    ForEach(Array(DurationOption.allCases.enumerated()), id: \.element.id) { index, option in
                        Text(option.tickLabel)
                            .font(Theme.display(13, option == model.duration ? .bold : .medium))
                            .foregroundStyle(option == model.duration ? Theme.ember : Theme.inkFaint)
                            .frame(maxWidth: .infinity,
                                   alignment: alignment(for: index))
                    }
                }
            }
            // A slider that snaps should feel like it snaps.
            .sensoryFeedback(.selection, trigger: model.duration)
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .cozyCard()
    }

    /// Ticks sit under the thumb positions, so the outer two hug the ends.
    private func alignment(for index: Int) -> Alignment {
        switch index {
        case 0: return .leading
        case DurationOption.allCases.count - 1: return .trailing
        default: return .center
        }
    }

    // MARK: - Status and action

    @ViewBuilder private var status: some View {
        if let message = statusMessage {
            VStack(spacing: 8) {
                Text(message)
                    .font(Theme.display(14, .medium))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                recovery
            }
            .transition(.opacity)
        }
    }

    private var generateButton: some View {
        Button(action: generate) {
            Group {
                if model.isGenerating {
                    ProgressView().tint(Theme.onEmber)
                } else {
                    Text("Generate")
                        .font(Theme.display(20, .bold))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .foregroundStyle(Theme.onEmber)
            .background(location.isUsable ? Theme.ember : Theme.ember.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .disabled(!location.isUsable || model.isGenerating)
        .sensoryFeedback(.success, trigger: model.loops.count)
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
                Link("Open Settings", destination: url)
                    .font(Theme.display(14, .bold))
                    .foregroundStyle(Theme.ember)
            }
        case .failed:
            Button("Try Again") { location.start() }
                .font(Theme.display(14, .bold))
                .foregroundStyle(Theme.ember)
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
