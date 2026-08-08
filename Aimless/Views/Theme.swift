import SwiftUI

/// One place for the palette so the two screens can't drift apart.
///
/// The app commits to a single dark, warm look rather than adapting to light
/// mode. That's deliberate: this is an app you open in a car, usually not at
/// noon, and a warm dusk palette is the point rather than a theme choice. Views
/// force `.preferredColorScheme(.dark)` so system controls match.
enum Theme {
    /// Night indigo at the top falling to ember at the bottom — dusk, roughly
    /// when you'd actually be going for a drive.
    static let backgroundTop = Color(red: 0.11, green: 0.10, blue: 0.17)
    static let backgroundMid = Color(red: 0.20, green: 0.14, blue: 0.20)
    static let backgroundBottom = Color(red: 0.35, green: 0.19, blue: 0.15)

    /// Warm off-white. Pure white is clinical and fights the warmth.
    static let ink = Color(red: 0.96, green: 0.93, blue: 0.88)
    static let inkSoft = Color(red: 0.80, green: 0.73, blue: 0.68)
    static let inkFaint = Color(red: 0.62, green: 0.55, blue: 0.52)

    /// The one saturated color in the app. Everything else is a neutral.
    static let ember = Color(red: 0.93, green: 0.61, blue: 0.29)
    static let onEmber = Color(red: 0.16, green: 0.09, blue: 0.05)

    /// Matches the start marker in the app icon and the map flag.
    static let start = Color(red: 0.19, green: 0.82, blue: 0.35)

    static let surface = Color.white.opacity(0.07)
    static let hairline = Color.white.opacity(0.13)

    static var background: some View {
        LinearGradient(
            stops: [
                .init(color: backgroundTop, location: 0),
                .init(color: backgroundMid, location: 0.55),
                .init(color: backgroundBottom, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    /// Rounded throughout. The default face is fine but reads like a settings
    /// screen; rounded reads like something you'd use on a weekend.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// Soft card used for the map and the stat row.
struct CozyCard: ViewModifier {
    var radius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}

extension View {
    func cozyCard(radius: CGFloat = 24) -> some View {
        modifier(CozyCard(radius: radius))
    }
}
