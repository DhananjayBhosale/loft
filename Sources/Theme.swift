import SwiftUI
import CoreText

/// "Command Deck" look: near-black canvas, soft surfaces, neon accents, big rounded numerals.
/// Type: Bricolage Grotesque (display + numerals), Schibsted Grotesk (UI), Spline Sans Mono (paths).
/// All three are open-source (SIL OFL) and bundled in the app.
enum Typo {
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font { .custom("Bricolage Grotesque", size: size).weight(weight) }
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .custom("Schibsted Grotesk", size: size).weight(weight) }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .custom("Spline Sans Mono", size: size).weight(weight) }

    static func register() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for f in files where f.pathExtension == "ttf" { CTFontManagerRegisterFontsForURL(f as CFURL, .process, nil) }
    }
}

typealias RGBA = (Double, Double, Double, Double)

/// A colour that resolves differently in dark and light appearance.
func adaptive(dark d: RGBA, light l: RGBA) -> Color {
    Color(nsColor: NSColor(name: nil) { ap in
        let c = ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? d : l
        return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: c.3)
    })
}

/// Same hue in both modes; the light version is deepened so it stays readable on paper-white.
func hue(_ r: Double, _ g: Double, _ b: Double) -> Color {
    adaptive(dark: (r, g, b, 1), light: (r * 0.66, g * 0.69, b * 0.72, 1))
}

enum Theme {
    // Dark: warm graphite. Light: warm paper. One calm blue; green/amber/red only ever mean safe / look first / destructive.
    static let bg = adaptive(dark: (0.094, 0.090, 0.086, 1), light: (0.957, 0.949, 0.933, 1))
    static let surface = adaptive(dark: (0.125, 0.120, 0.114, 1), light: (0.999, 0.997, 0.992, 1))
    static let surface2 = adaptive(dark: (0.165, 0.158, 0.150, 1), light: (0.925, 0.917, 0.895, 1))
    static let rail = adaptive(dark: (0, 0, 0, 0.28), light: (0.918, 0.908, 0.882, 1))
    static let well = adaptive(dark: (0, 0, 0, 0.30), light: (0, 0, 0, 0.06))
    static let stroke = adaptive(dark: (1, 0.95, 0.88, 0.09), light: (0.2, 0.17, 0.12, 0.12))
    static let ink = adaptive(dark: (1, 0.97, 0.93, 1), light: (0.11, 0.105, 0.095, 1))
    static let onAccent = adaptive(dark: (0, 0, 0, 0.82), light: (1, 1, 1, 1))
    static let muted = ink.opacity(0.62)
    static let faint = ink.opacity(0.52)

    static let mint = adaptive(dark: (0.47, 0.80, 0.60, 1), light: (0.09, 0.50, 0.30, 1))     // safe
    static let amber = adaptive(dark: (0.93, 0.69, 0.33, 1), light: (0.74, 0.42, 0.02, 1))    // look first
    static let violet = adaptive(dark: (0.42, 0.62, 0.98, 1), light: (0.14, 0.37, 0.86, 1))   // the one accent (blue)
    static let pink = adaptive(dark: (0.92, 0.42, 0.38, 1), light: (0.79, 0.19, 0.17, 1))     // destructive (red)
    static let cyan = adaptive(dark: (0.45, 0.72, 0.88, 1), light: (0.07, 0.46, 0.64, 1))
    static let kept = adaptive(dark: (1, 0.97, 0.93, 0.26), light: (0.2, 0.17, 0.12, 0.22))

    static let brand = LinearGradient(colors: [violet, violet], startPoint: .top, endPoint: .bottom)
    static let fresh = LinearGradient(colors: [mint, mint], startPoint: .top, endPoint: .bottom)
    static let warm = LinearGradient(colors: [pink, pink], startPoint: .top, endPoint: .bottom)
}

struct Bento: ViewModifier {
    var pad: CGFloat
    func body(content: Content) -> some View {
        content
            .padding(pad)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
    }
}
extension View {
    func bento(_ pad: CGFloat = 18) -> some View { modifier(Bento(pad: pad)) }
}

struct GlowButtonStyle: ButtonStyle {
    var gradient: LinearGradient = Theme.brand
    var glow: Color = Theme.violet
    var dark = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.ui(13, .semibold))
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(gradient))
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.35)
    }
}

struct GhostButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.ui(13, .medium))
            .foregroundStyle(Theme.ink.opacity(0.9))
            .padding(.horizontal, 13).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.ink.opacity(configuration.isPressed ? 0.12 : 0.04)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.stroke.opacity(1.8), lineWidth: 1))
            .opacity(enabled ? 1 : 0.35)
    }
}

struct IconButtonStyle: ButtonStyle {
    var tint: Color = Theme.ink
    func makeBody(configuration: Configuration) -> some View { HoverIcon(configuration: configuration, tint: tint) }
    struct HoverIcon: View {
        let configuration: Configuration
        let tint: Color
        @State private var hover = false
        var body: some View {
            configuration.label
                .foregroundStyle(tint.opacity(hover ? 1 : 0.7))
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill((tint == Color.white ? Color.white : Theme.ink).opacity(configuration.isPressed ? 0.28 : hover ? 0.2 : 0.1)))
                .onHover { hover = $0 }
        }
    }
}

struct RoundCheckStyle: ToggleStyle {
    var tint: Color = Theme.mint
    var icon: Glyph = .check
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(configuration.isOn ? tint : Theme.ink.opacity(0.3), lineWidth: 1.5)
                if configuration.isOn {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(tint)
                    Icon(glyph: icon, size: 11).foregroundStyle(Theme.onAccent)
                }
            }
            .frame(width: 18, height: 18)
            .frame(width: 32, height: 32).contentShape(Rectangle())
            .animation(.snappy(duration: 0.15), value: configuration.isOn)
        }
        .buttonStyle(.plain)
    }
}

struct Segmented<T: Hashable>: View {
    let options: [T]
    let label: (T) -> String
    @Binding var selection: T
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { o in
                Button { withAnimation(.snappy(duration: 0.2)) { selection = o } } label: {
                    Text(label(o))
                        .font(Typo.ui(13, .medium))
                        .foregroundStyle(selection == o ? Theme.ink : Theme.muted)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background {
                            if selection == o { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.ink.opacity(0.12)).matchedGeometryEffect(id: "seg", in: ns) }
                        }
                }.buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.well))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
    }
}

struct Chip: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(Typo.ui(11, .semibold))
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(color.opacity(0.14)))
            .foregroundStyle(color)
    }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Typo.display(30, .bold))
                Text(subtitle).font(Typo.ui(13)).foregroundStyle(Theme.muted)
            }
            Spacer()
            trailing
        }
    }
}

/// Segmented donut used for the disk overview.
struct Ring: View {
    let parts: [(Double, Color)]
    var lineWidth: CGFloat = 14
    var body: some View {
        ZStack {
            Circle().stroke(Theme.surface2, lineWidth: lineWidth)
            ForEach(Array(parts.enumerated()), id: \.offset) { i, p in
                let start = parts[..<i].reduce(0) { $0 + $1.0 }
                Circle()
                    .trim(from: start, to: max(start, start + p.0 - 0.006))
                    .stroke(p.1, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
        .animation(.spring(duration: 0.8), value: parts.map(\.0))
    }
}
