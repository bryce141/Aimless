import MapKit
import SwiftUI
import UIKit

struct GenerateView: View {
    @State private var location = LocationProvider()
    @State private var model = LoopViewModel()
    @State private var showResults = false
    /// Set when Generate is tapped without a location fix behind it.
    @State private var blocked = false

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

    /// `-duration 120` preselects a picker option. Store screenshots need to
    /// show more than whatever the default happens to be, and the slider can't
    /// be dragged from a script.
    private var forcedDuration: DurationOption? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-duration"), i + 1 < args.count,
              let raw = Int(args[i + 1]) else { return nil }
        return DurationOption(rawValue: raw)
    }
    #endif

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background

                // Map and picker read as one block — "here, and for this long"
                // — with the action pinned below them. The map takes the slack
                // rather than a Spacer, so leftover space on a big phone
                // becomes more map instead of a dead gap above the button.
                //
                // `minHeight` is deliberately low. This is an iPhone-only
                // binary, so on an iPad it runs in a compatibility window that
                // is shorter than any iPhone. At a 240pt floor the extra two
                // lines of a location status message overflowed the window and
                // clipped both the title and the Generate button off their
                // edges — App Review tapped the half-visible button and
                // reported that nothing happened.
                VStack(spacing: 0) {
                    header
                    map
                        .frame(minHeight: 150, maxHeight: .infinity)
                        .cozyCard()
                        .padding(.top, 18)

                    durationPicker
                        .padding(.top, 16)
                }
                .padding(.horizontal, 24)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            // Pinned rather than stacked. The action reserves its own space
            // before the map and picker get any, so no combination of status
            // text and window height can push it off screen.
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 14) {
                    status
                    generateButton
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showResults) {
                LoopResultsView(loops: model.loops, duration: model.duration)
            }
            .alert("Can\u{2019}t generate yet", isPresented: $blocked) {
                switch location.status {
                case .denied, .reducedAccuracy:
                    Button("Open Settings") { openSettings() }
                    Button("Not Now", role: .cancel) {}
                default:
                    Button("OK", role: .cancel) {}
                }
            } message: {
                Text(blockedReason)
            }
            .onAppear {
                location.start()
                #if DEBUG
                if let forced = forcedDuration { model.duration = forced }
                #endif
            }
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
        // Disabled only while a generate is already running. A button that is
        // visible, looks like a button, and does literally nothing on tap is
        // indistinguishable from a broken app — which is exactly how App Review
        // described it. Without a fix the tap now explains itself.
        .disabled(model.isGenerating)
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

    /// Why the tap could not do anything, in the same words the status line
    /// uses, so the alert and the screen never contradict each other.
    private var blockedReason: String {
        switch location.status {
        case .locating:
            return "Aimless is still finding you. Give it a moment and tap Generate again."
        case .ready:
            return "Aimless doesn\u{2019}t have a location fix yet. Tap Generate again in a moment."
        default:
            return statusMessage ?? ""
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
        guard location.isUsable, let origin = location.current else {
            // Retry first: `.locating` and `.failed` both clear on their own
            // once a fix lands, and a stale `.failed` is one request away from
            // working. Then say something, because silence here is the defect.
            location.start()
            blocked = true
            return
        }
        Task {
            await model.generate(from: origin)
            if model.hasResults { showResults = true }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    GenerateView()
}
