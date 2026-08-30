import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct GenerateView: View {
    @State private var location = LocationProvider()
    @State private var model = LoopViewModel()
    @State private var showResults = false

    /// Why the last tap could not start a generate, or `nil` if nothing is
    /// wrong. **Optional rather than `Bool`, and drawn inline rather than
    /// presented.**
    ///
    /// Both of those are scar tissue. 1.0 (4) raised this as a SwiftUI
    /// `.alert(isPresented:)` driven by a `Bool`, and App Review reported the
    /// same "nothing happened when we tapped generate" it was written to fix.
    /// Two things went wrong at once:
    ///
    /// 1. SwiftUI silently drops an alert presentation while something else is
    ///    presenting — above all the system location permission prompt, which
    ///    is on screen for exactly the first few seconds anyone uses the app.
    /// 2. The flag stayed `true` afterwards, so every later tap re-assigned
    ///    `true`, produced no state *change*, and therefore asked SwiftUI for
    ///    nothing. The button went permanently silent.
    ///
    /// An optional cannot latch the same way — each tap writes a fresh value —
    /// and inline content renders underneath a system alert instead of losing
    /// to it. Both the failure and this fix were reproduced on an iPad Air
    /// simulator before shipping.
    @State private var note: BlockNote?

    /// Bumped on every tap that does not start a generate immediately, purely
    /// so haptic feedback re-fires when the note itself has not changed. Two
    /// taps in the same state must still feel like two taps.
    @State private var tapNonce = 0

    /// A tap made before the location fix landed, remembered so it can run when
    /// the fix arrives.
    ///
    /// This is the difference between "nothing happened" and "it worked, a
    /// second later". A Wi-Fi-only iPad has no GPS and infers position from
    /// nearby networks, so the gap between opening the app and having a usable
    /// coordinate is routinely seconds — and it is precisely the window a
    /// reviewer taps in.
    @State private var pendingGenerate = false
    @State private var pendingToken = 0

    /// How long a queued tap waits for a fix before giving up and saying so.
    /// Long enough for Wi-Fi positioning, short enough that the spinner is
    /// never mistaken for a hang.
    private static let fixWaitSeconds = 15

    @Environment(\.scenePhase) private var scenePhase

    #if DEBUG
    /// Screenshot automation. Launching with `-autoGenerate` taps Generate for
    /// us as soon as the app is up.
    ///
    /// This exists because there is no way to drive the simulator from a script
    /// otherwise: `simctl` has no tap command, and synthesising a click through
    /// System Events needs an accessibility grant a build machine won't have.
    /// DEBUG-only, so it cannot reach a release build.
    ///
    /// It no longer waits for `isUsable` itself — `generate()` queues the tap,
    /// which is the same path a real early tap takes, so the automation now
    /// exercises the interesting code instead of tiptoeing around it.
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
                .animation(.snappy(duration: 0.2), value: note)
                .animation(.snappy(duration: 0.2), value: pendingGenerate)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showResults) {
                LoopResultsView(loops: model.loops, duration: model.duration)
            }
            .onAppear {
                location.start()
                #if DEBUG
                if let forced = forcedDuration { model.duration = forced }
                if wantsAutoGenerate { generate() }
                #endif
            }
            // The fix is taken once. Without this, opening the app in the
            // driveway and generating an hour later somewhere else builds the
            // loop around the driveway.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { location.start() }
            }
            // The queued tap, redeemed. Anything waiting on a fix runs the
            // moment one lands.
            .onChange(of: location.isUsable) { _, usable in
                guard usable else { return }
                redeemPendingGenerate()
            }
            // A queued tap that can never succeed should say so immediately
            // rather than sitting out the full timeout.
            .onChange(of: location.status) { _, status in
                guard pendingGenerate else { return }
                switch status {
                case .denied:           resolvePending(with: .denied)
                case .reducedAccuracy:  resolvePending(with: .reducedAccuracy)
                case .failed:           resolvePending(with: .fixFailed)
                case .locating, .ready: break
                }
            }
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

    /// One slot above the button, with a strict priority order so two things
    /// never argue over it: a blocked tap, then a failed generate, then the
    /// ambient location state.
    ///
    /// Everything here is ordinary inline content. Nothing in this app reports
    /// a problem through a presentation any more — see `note`.
    @ViewBuilder private var status: some View {
        if let note {
            callout(symbol: note.symbol, message: note.message, action: note.action)
        } else if let error = model.errorMessage {
            // A failed generate used to be one grey line at the same weight as
            // the picker's caption, which is easy to read as "nothing
            // happened". A generate that cost the user a wait and produced no
            // route deserves the same callout as anything else that went
            // wrong.
            callout(symbol: "exclamationmark.triangle.fill",
                    message: error,
                    action: .tryAgain)
        } else if let ambient = ambientMessage {
            Text(ambient)
                .font(Theme.display(14, .medium))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .transition(.opacity)
        }
    }

    private var generateButton: some View {
        Button(action: generate) {
            Group {
                if model.isGenerating {
                    ProgressView().tint(Theme.onEmber)
                } else if pendingGenerate {
                    // The tap is not lost, it is waiting. Saying so on the
                    // control that was tapped is the most direct answer
                    // available to "did that do anything?".
                    HStack(spacing: 10) {
                        ProgressView().tint(Theme.onEmber)
                        Text("Finding you\u{2026}")
                            .font(Theme.display(20, .bold))
                    }
                } else {
                    Text("Generate")
                        .font(Theme.display(20, .bold))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .foregroundStyle(Theme.onEmber)
            .background(Theme.ember)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        // Disabled only while a generate is already running, and never dimmed
        // otherwise. A tap is meaningful in every other state — it either
        // generates, queues, or explains itself — so the button should never
        // look unavailable.
        .disabled(model.isGenerating)
        .sensoryFeedback(.success, trigger: model.loops.count)
        .sensoryFeedback(.impact, trigger: tapNonce)
    }

    /// The quiet line, for states that are nobody's fault and not a response to
    /// a tap.
    private var ambientMessage: String? {
        switch location.status {
        case .locating: return "Finding you\u{2026}"
        case .denied, .reducedAccuracy, .failed, .ready: return nil
        }
    }

    private func callout(
        symbol: String,
        message: String,
        action: BlockNote.Action?
    ) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol)
                    .font(Theme.display(15, .bold))
                    .foregroundStyle(Theme.ember)
                Text(message)
                    .font(Theme.display(14, .medium))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let action {
                Button(action.title) { perform(action) }
                    .font(Theme.display(14, .bold))
                    .foregroundStyle(Theme.ember)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Theme.ember.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.ember.opacity(0.45), lineWidth: 1)
        )
        .transition(.opacity)
    }

    // MARK: - Actions

    private func generate() {
        guard !model.isGenerating else { return }

        if location.isUsable, let origin = location.current {
            note = nil
            pendingGenerate = false
            run(from: origin)
            return
        }

        // No fix behind the tap. Every branch from here has to change something
        // on screen; silence is the defect this whole file is organised around.
        tapNonce += 1
        model.errorMessage = nil

        switch location.status {
        case .denied:
            pendingGenerate = false
            note = .denied
        case .reducedAccuracy:
            pendingGenerate = false
            note = .reducedAccuracy
        case .locating, .failed, .ready:
            // A fix is still reachable, so treat the tap as an instruction
            // rather than a rejection: retry the request and run as soon as one
            // lands. `.failed` is included deliberately — a stale failure is one
            // request away from working.
            note = nil
            pendingGenerate = true
            pendingToken += 1
            location.start()
            armPendingTimeout(pendingToken)
        }
    }

    private func run(from origin: CLLocationCoordinate2D) {
        Task {
            await model.generate(from: origin)
            if model.hasResults { showResults = true }
        }
    }

    private func redeemPendingGenerate() {
        guard pendingGenerate, !model.isGenerating,
              let origin = location.current else { return }
        pendingGenerate = false
        note = nil
        run(from: origin)
    }

    /// Backstop for a queued tap when the fix never arrives and CoreLocation
    /// never reports a failure either — which it does not always do. Without
    /// this the button spins indefinitely, which is its own version of nothing
    /// happening.
    private func armPendingTimeout(_ token: Int) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.fixWaitSeconds))
            guard pendingGenerate, pendingToken == token else { return }
            resolvePending(with: .fixFailed)
        }
    }

    private func resolvePending(with note: BlockNote) {
        pendingGenerate = false
        self.note = note
    }

    private func perform(_ action: BlockNote.Action) {
        switch action {
        case .openSettings:
            openSettings()
        case .tryAgain:
            note = nil
            model.errorMessage = nil
            generate()
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Block notes

/// The reasons a tap on Generate can fail to start one, and what to offer the
/// user about each. A type rather than loose strings, so adding a state without
/// deciding what it says on screen is a compile error.
private enum BlockNote: Equatable {
    case denied
    case reducedAccuracy
    case fixFailed

    enum Action: Equatable {
        case openSettings
        case tryAgain

        var title: String {
            switch self {
            case .openSettings: return "Open Settings"
            case .tryAgain: return "Try Again"
            }
        }
    }

    var symbol: String {
        switch self {
        case .denied, .reducedAccuracy: return "location.slash.fill"
        case .fixFailed: return "location.magnifyingglass"
        }
    }

    var message: String {
        switch self {
        case .denied:
            return "Aimless needs location access to start a loop where you are. Turn it on in Settings, then tap Generate again."
        case .reducedAccuracy:
            return "Precise Location is off, so we can\u{2019}t tell where the loop should start. Turn it on for Aimless in Settings."
        case .fixFailed:
            return "Couldn\u{2019}t get a location fix. Somewhere with a clearer view of the sky usually does it."
        }
    }

    var action: Action? {
        switch self {
        case .denied, .reducedAccuracy: return .openSettings
        case .fixFailed: return .tryAgain
        }
    }
}

#Preview {
    GenerateView()
}
