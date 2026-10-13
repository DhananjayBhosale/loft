import SwiftUI

/// Our own icon set. Drawn as strokes on a 1×1 grid with round caps, plus one small filled dot per icon as a signature.
enum Glyph {
    case logo, overview, nas, duplicates, biggest
    case up, home, plus, trash, close, search, check, spark, upload, tray
    case folder, file, film, photo, box, music, doc, app
    case cache, log, build, download, device, archive
    case sun, moon, auto
}

struct GlyphShape: Shape {
    let glyph: Glyph
    func path(in r: CGRect) -> Path {
        let s = min(r.width, r.height)
        let ox = r.midX - s / 2, oy = r.midY - s / 2
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        var p = Path()
        func m(_ x: CGFloat, _ y: CGFloat) { p.move(to: P(x, y)) }
        func l(_ x: CGFloat, _ y: CGFloat) { p.addLine(to: P(x, y)) }
        func q(_ cx: CGFloat, _ cy: CGFloat, _ x: CGFloat, _ y: CGFloat) { p.addQuadCurve(to: P(x, y), control: P(cx, cy)) }
        func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ rad: CGFloat) {
            p.addRoundedRect(in: CGRect(x: ox + x * s, y: oy + y * s, width: w * s, height: h * s), cornerSize: CGSize(width: rad * s, height: rad * s))
        }
        func poly(_ pts: [(CGFloat, CGFloat)], close: Bool = false) {
            guard let f = pts.first else { return }
            m(f.0, f.1); for q in pts.dropFirst() { l(q.0, q.1) }
            if close { p.closeSubpath() }
        }
        func arc(_ cx: CGFloat, _ cy: CGFloat, _ rad: CGFloat, _ a0: Double, _ a1: Double) {
            p.addArc(center: P(cx, cy), radius: rad * s, startAngle: .degrees(a0), endAngle: .degrees(a1), clockwise: false)
        }
        func c(_ c1x: CGFloat, _ c1y: CGFloat, _ c2x: CGFloat, _ c2y: CGFloat, _ x: CGFloat, _ y: CGFloat) { p.addCurve(to: P(x, y), control1: P(c1x, c1y), control2: P(c2x, c2y)) }
        func ring(_ cx: CGFloat, _ cy: CGFloat, _ rad: CGFloat) { p.addEllipse(in: CGRect(x: ox + (cx - rad) * s, y: oy + (cy - rad) * s, width: 2 * rad * s, height: 2 * rad * s)) }

        switch glyph {
        case .logo:
            poly([(0.24, 0.50), (0.5, 0.24), (0.76, 0.50)]); poly([(0.24, 0.72), (0.5, 0.46), (0.76, 0.72)])
        case .overview:
            ring(0.5, 0.5, 0.34); poly([(0.5, 0.5), (0.74, 0.30)]); ring(0.5, 0.5, 0.06)
        case .nas:
            rr(0.16, 0.58, 0.68, 0.26, 0.07)
            poly([(0.5, 0.46), (0.5, 0.14)]); poly([(0.36, 0.28), (0.5, 0.14), (0.64, 0.28)])
        case .duplicates:
            rr(0.14, 0.38, 0.46, 0.46, 0.08)
            m(0.38, 0.30); l(0.38, 0.22); q(0.38, 0.14, 0.46, 0.14); l(0.78, 0.14); q(0.86, 0.14, 0.86, 0.22); l(0.86, 0.54); q(0.86, 0.62, 0.78, 0.62); l(0.68, 0.62)
        case .biggest:
            poly([(0.25, 0.86), (0.25, 0.14)]); poly([(0.50, 0.86), (0.50, 0.40)]); poly([(0.75, 0.86), (0.75, 0.62)])
        case .up:
            poly([(0.24, 0.62), (0.5, 0.36), (0.76, 0.62)])
        case .home:
            poly([(0.14, 0.50), (0.5, 0.16), (0.86, 0.50)]); poly([(0.24, 0.44), (0.24, 0.84), (0.76, 0.84), (0.76, 0.44)])
        case .plus:
            poly([(0.5, 0.2), (0.5, 0.8)]); poly([(0.2, 0.5), (0.8, 0.5)])
        case .trash:
            poly([(0.2, 0.28), (0.8, 0.28)]); poly([(0.40, 0.28), (0.40, 0.17), (0.60, 0.17), (0.60, 0.28)])
            poly([(0.27, 0.28), (0.31, 0.84), (0.69, 0.84), (0.73, 0.28)])
        case .close:
            poly([(0.27, 0.27), (0.73, 0.73)]); poly([(0.73, 0.27), (0.27, 0.73)])
        case .search:
            ring(0.44, 0.44, 0.27); poly([(0.64, 0.64), (0.84, 0.84)])
        case .check:
            poly([(0.22, 0.52), (0.43, 0.72), (0.78, 0.30)])
        case .spark:
            m(0.5, 0.12); q(0.54, 0.46, 0.88, 0.5); q(0.54, 0.54, 0.5, 0.88); q(0.46, 0.54, 0.12, 0.5); q(0.46, 0.46, 0.5, 0.12)
        case .upload:
            poly([(0.5, 0.66), (0.5, 0.18)]); poly([(0.32, 0.36), (0.5, 0.18), (0.68, 0.36)]); poly([(0.18, 0.80), (0.82, 0.80)])
        case .tray:
            poly([(0.14, 0.56), (0.30, 0.56), (0.36, 0.68), (0.64, 0.68), (0.70, 0.56), (0.86, 0.56)])
            poly([(0.20, 0.24), (0.80, 0.24), (0.86, 0.56), (0.86, 0.80), (0.14, 0.80), (0.14, 0.56)], close: true)
        case .folder:
            m(0.12, 0.30); q(0.12, 0.22, 0.20, 0.22); l(0.38, 0.22); l(0.48, 0.32); l(0.80, 0.32); q(0.88, 0.32, 0.88, 0.40); l(0.88, 0.72); q(0.88, 0.80, 0.80, 0.80); l(0.20, 0.80); q(0.12, 0.80, 0.12, 0.72); p.closeSubpath()
        case .file:
            poly([(0.24, 0.14), (0.56, 0.14), (0.78, 0.36), (0.78, 0.84), (0.24, 0.84)], close: true); poly([(0.56, 0.14), (0.56, 0.36), (0.78, 0.36)])
        case .film:
            rr(0.14, 0.20, 0.72, 0.60, 0.08); poly([(0.34, 0.20), (0.34, 0.80)]); poly([(0.66, 0.20), (0.66, 0.80)])
        case .photo:
            rr(0.14, 0.20, 0.72, 0.60, 0.08); poly([(0.14, 0.70), (0.36, 0.46), (0.52, 0.62), (0.64, 0.50), (0.86, 0.72)])
        case .box:
            poly([(0.5, 0.14), (0.84, 0.32), (0.84, 0.68), (0.5, 0.86), (0.16, 0.68), (0.16, 0.32)], close: true)
            poly([(0.16, 0.32), (0.5, 0.50), (0.84, 0.32)]); poly([(0.5, 0.50), (0.5, 0.86)])
        case .music:
            poly([(0.40, 0.72), (0.40, 0.22), (0.80, 0.16), (0.80, 0.66)]); ring(0.30, 0.74, 0.10); ring(0.70, 0.68, 0.10)
        case .doc:
            poly([(0.24, 0.14), (0.56, 0.14), (0.78, 0.36), (0.78, 0.84), (0.24, 0.84)], close: true); poly([(0.56, 0.14), (0.56, 0.36), (0.78, 0.36)])
            poly([(0.36, 0.56), (0.66, 0.56)]); poly([(0.36, 0.70), (0.54, 0.70)])
        case .app:
            rr(0.16, 0.16, 0.68, 0.68, 0.18)
        case .cache:
            poly([(0.16, 0.34), (0.5, 0.20), (0.84, 0.34), (0.5, 0.48)], close: true)
            poly([(0.16, 0.50), (0.5, 0.64), (0.84, 0.50)]); poly([(0.16, 0.66), (0.5, 0.80), (0.84, 0.66)])
        case .log:
            rr(0.20, 0.14, 0.60, 0.72, 0.10); poly([(0.34, 0.36), (0.66, 0.36)]); poly([(0.34, 0.52), (0.66, 0.52)]); poly([(0.34, 0.68), (0.50, 0.68)])
        case .build:
            rr(0.14, 0.54, 0.34, 0.28, 0.05); rr(0.52, 0.54, 0.34, 0.28, 0.05); rr(0.33, 0.20, 0.34, 0.28, 0.05)
        case .download:
            poly([(0.5, 0.16), (0.5, 0.60)]); poly([(0.32, 0.44), (0.5, 0.62), (0.68, 0.44)]); poly([(0.20, 0.70), (0.20, 0.82), (0.80, 0.82), (0.80, 0.70)])
        case .device:
            rr(0.30, 0.12, 0.40, 0.76, 0.10); poly([(0.43, 0.23), (0.57, 0.23)])
        case .sun:
            ring(0.5, 0.5, 0.17)
            for i in 0..<8 {
                let a = Double(i) * .pi / 4, ca = CGFloat(cos(a)), sa = CGFloat(sin(a))
                poly([(0.5 + 0.30 * ca, 0.5 + 0.30 * sa), (0.5 + 0.42 * ca, 0.5 + 0.42 * sa)])
            }
        case .moon:
            m(0.62, 0.14); c(0.30, 0.20, 0.18, 0.52, 0.30, 0.70); c(0.42, 0.88, 0.70, 0.90, 0.84, 0.66); c(0.56, 0.72, 0.42, 0.40, 0.62, 0.14); p.closeSubpath()
        case .auto:
            ring(0.5, 0.5, 0.34); poly([(0.5, 0.16), (0.5, 0.84)]); poly([(0.24, 0.5), (0.5, 0.5)])
        case .archive:
            rr(0.14, 0.20, 0.72, 0.20, 0.05); rr(0.20, 0.40, 0.60, 0.42, 0.05); poly([(0.42, 0.56), (0.58, 0.56)])
        }
        return p
    }
}

struct GlyphDots: Shape {
    let glyph: Glyph
    func path(in r: CGRect) -> Path {
        let s = min(r.width, r.height)
        let ox = r.midX - s / 2, oy = r.midY - s / 2
        var p = Path()
        func d(_ x: CGFloat, _ y: CGFloat, _ rad: CGFloat) {
            p.addEllipse(in: CGRect(x: ox + (x - rad) * s, y: oy + (y - rad) * s, width: 2 * rad * s, height: 2 * rad * s))
        }
        switch glyph {
        case .logo: d(0.5, 0.86, 0.055)
        case .overview: d(0.5, 0.5, 0.06)
        case .nas: d(0.72, 0.71, 0.04)
        case .duplicates: d(0.37, 0.61, 0.05)
        case .biggest: d(0.75, 0.46, 0.045)
        case .home: d(0.5, 0.66, 0.05)
        case .folder: d(0.25, 0.47, 0.04)
        case .film: d(0.50, 0.50, 0.06)
        case .photo: d(0.68, 0.36, 0.06)
        case .file: d(0.46, 0.60, 0.05)
        case .app: d(0.50, 0.50, 0.09)
        case .spark: d(0.80, 0.22, 0.045)
        case .device: d(0.50, 0.76, 0.035)
        case .trash: d(0.50, 0.58, 0.04)
        case .box: d(0.50, 0.68, 0.0)
        default: break
        }
        return p
    }
}

struct Icon: View {
    let glyph: Glyph
    var size: CGFloat = 16
    var body: some View {
        ZStack {
            GlyphShape(glyph: glyph).stroke(.foreground, style: StrokeStyle(lineWidth: max(1.4, size * 0.085), lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
    }
}
