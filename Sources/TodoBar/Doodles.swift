import SwiftUI

/// Chat-wallpaper style: a soft gradient under a repeating tile of hand-drawn line doodles.
struct DoodleBackground: View {
    let shape: UnevenRoundedRectangle
    let theme: Theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = DoodlePalette(theme: theme, dark: colorScheme == .dark)
        ZStack {
            shape.fill(LinearGradient(colors: palette.background,
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            Canvas { context, size in
                let style = StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round)
                for origin in TileScatter.origins(tile: DoodleTile.size, covering: size) {
                    context.stroke(DoodleTile.path.offsetBy(dx: origin.x, dy: origin.y),
                                   with: .color(palette.ink), style: style)
                }
            }
            .clipShape(shape)
        }
        .allowsHitTesting(false)
    }
}

private struct DoodlePalette {
    let background: [Color]
    /// Kept faint so task text stays easy to read on top.
    let ink: Color

    init(theme: Theme, dark: Bool) {
        if theme == .pink {
            background = [Color(red: 1.0, green: 0.88, blue: 0.92), Color(red: 0.99, green: 0.93, blue: 0.95)]
            ink = Color(red: 0.78, green: 0.36, blue: 0.50).opacity(0.16)
        } else if dark {
            background = [Color(red: 0.09, green: 0.09, blue: 0.10), Color(red: 0.04, green: 0.04, blue: 0.05)]
            ink = Color(red: 0.66, green: 0.56, blue: 0.47).opacity(0.22)
        } else {
            background = [Color(red: 0.86, green: 0.92, blue: 0.79), Color(red: 0.95, green: 0.92, blue: 0.81)]
            ink = Color(red: 0.30, green: 0.40, blue: 0.22).opacity(0.15)
        }
    }
}

/// One repeating tile of doodles, with small dots, sparkles and squiggles in the gaps.
private enum DoodleTile {
    static let size = CGSize(width: 320, height: 384)

    static let path: Path = {
        let scatter = TileScatter(size: size, columns: 5, rows: 6, jitter: 10, tilt: 25, scale: 1.1...1.35,
                                  motifs: Doodles.all, fillers: Doodles.fillers, fillerCount: 70, seed: 7)
        var tile = Path()
        for placement in scatter.motifs {
            tile.addPath(Doodles.all[placement.index], transform: placement.transform)
        }
        for placement in scatter.fillers {
            tile.addPath(Doodles.fillers[placement.index], transform: placement.transform)
        }
        return tile
    }()
}

/// Lays motifs out over a repeating tile: one per cell of a staggered grid, nudged, tilted and
/// sized a little at random, then fillers wherever they fit. Footprints are checked against
/// the copies in the neighbouring tiles too, so nothing collides across a tile edge.
struct TileScatter {
    struct Placement {
        let index: Int
        let transform: CGAffineTransform
    }

    private(set) var motifs: [Placement] = []
    private(set) var fillers: [Placement] = []

    init(size: CGSize, columns: Int, rows: Int, jitter: CGFloat, tilt: CGFloat, scale: ClosedRange<CGFloat>,
         motifs motifShapes: [Path], fillers fillerShapes: [Path], fillerCount: Int, seed: UInt64) {
        var occupied: [CGRect] = []
        let cellW = size.width / CGFloat(columns), cellH = size.height / CGFloat(rows)
        var random = SplitMix(seed: seed)

        func occupy(_ shape: Path, _ transform: CGAffineTransform) {
            let bounds = shape.applying(transform).boundingRect.insetBy(dx: 2, dy: 2)
            for dx in [-size.width, 0, size.width] {
                for dy in [-size.height, 0, size.height] {
                    occupied.append(bounds.offsetBy(dx: dx, dy: dy))
                }
            }
        }

        for row in 0..<rows where !motifShapes.isEmpty {
            for col in 0..<columns {
                let index = (row * columns + col) % motifShapes.count
                let x = (CGFloat(col) + (row.isMultiple(of: 2) ? 0.5 : 1)) * cellW + random.next(-jitter, jitter)
                let y = (CGFloat(row) + 0.5) * cellH + random.next(-jitter * 0.9, jitter * 0.9)
                let angle = random.next(-tilt, tilt)
                let factor = random.next(scale.lowerBound, scale.upperBound)
                let transform = CGAffineTransform(translationX: x, y: y)
                    .rotated(by: angle * .pi / 180)
                    .scaledBy(x: factor, y: factor)
                motifs.append(Placement(index: index, transform: transform))
                occupy(motifShapes[index], transform)
            }
        }

        var attempts = 0
        while fillers.count < fillerCount && attempts < 600 {
            attempts += 1
            let index = fillers.count % fillerShapes.count
            let transform = CGAffineTransform(translationX: random.next(0, size.width), y: random.next(0, size.height))
            let bounds = fillerShapes[index].applying(transform).boundingRect.insetBy(dx: -3, dy: -3)
            guard !occupied.contains(where: { $0.intersects(bounds) }) else { continue }
            fillers.append(Placement(index: index, transform: transform))
            occupy(fillerShapes[index], transform)
        }
    }

    /// Where to draw each copy of a tile to cover `size`, starting one tile up and left so
    /// motifs straddling a tile edge are drawn whole.
    static func origins(tile: CGSize, covering size: CGSize) -> [CGPoint] {
        var origins: [CGPoint] = []
        var y = -tile.height
        while y < size.height {
            var x = -tile.width
            while x < size.width {
                origins.append(CGPoint(x: x, y: y))
                x += tile.width
            }
            y += tile.height
        }
        return origins
    }
}

/// Deterministic jitter, so the pattern is the same on every launch.
private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next(_ low: CGFloat, _ high: CGFloat) -> CGFloat {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return low + (high - low) * CGFloat(z >> 11) / CGFloat(1 << 53)
    }
}

// MARK: - Drawings

/// Each doodle is drawn around the origin, roughly within ±22 points, in y-down coordinates.
private enum Doodles {
    static let all: [Path] = [
        whale, coffee, planet, cat, umbrella,
        rocket, checklist, fish, iceCream, cloud,
        balloon, donut, sailboat, lightbulb, heart,
        alarmClock, mushroom, paperPlane, gift, snail,
        moon, cactus, pencil, flower, leaf,
        music, camera, sun, headphones, dice,
    ]

    static let fillers: [Path] = [
        sketch { $0.circle(0, 0, 2.2) },
        sketch { $0.sparkle(0, 0, 4.5) },
        sketch { $0.circle(-3, 0, 1); $0.circle(3, -2, 1.6) },
        sketch { $0.spiral(0, 0, 4, turns: 1.6) },
        sketch { $0.star(0, 0, 4) },
        sketch { $0.m(-6, 0); $0.q(-2, 0, -4, -3); $0.q(2, 0, 0, 3); $0.q(6, 0, 4, -3) },
        sketch { $0.circle(0, 0, 1) },
    ]

    static let whale = sketch { p in
        p.m(14, -3)
        p.c(-20, 4, 10, -18, -17, -16)
        p.c(12, 8, -22, 16, 0, 16)
        p.q(20, -6, 19, 4)
        p.q(28, -13, 27, -6)
        p.q(20, -8, 24, -12)
        p.q(12, -13, 16, -12)
        p.q(14, -3, 12, -8)
        p.circle(-12, -1, 1.1)
        p.m(-19, 7); p.q(-12, 7, -15.5, 9.5)
        p.m(-14, 9.5); p.q(3, 9.5, -5, 12.5)
        p.m(-8, -12); p.q(-12, -19, -8, -17)
        p.m(-8, -12); p.q(-4, -19, -8, -17)
        p.m(-8, -12); p.l(-8, -20)
    }

    static let rocket = sketch { p in
        p.m(0, -20)
        p.q(6, 7, 11, -10)
        p.l(-6, 7)
        p.q(0, -20, -11, -10)
        p.circle(0, -7, 3.5)
        p.m(7, -2); p.l(12, 9); p.l(6.5, 6)
        p.m(-7, -2); p.l(-12, 9); p.l(-6.5, 6)
        p.m(-3.5, 7); p.q(0, 16, -3, 13); p.q(3.5, 7, 3, 13)
    }

    static let planet = sketch { p in
        p.circle(0, 0, 10)
        p.circle(-3, -3, 2)
        p.circle(4, 3.5, 1.2)
        let tilt = CGAffineTransform(rotationAngle: -0.35)
        var ring = Path()
        ring.ellipseArc(rx: 20, ry: 5.5, from: 0, to: .pi)
        ring.ellipseArc(rx: 20, ry: 5.5, from: .pi, to: .pi + 1.05)
        ring.ellipseArc(rx: 20, ry: 5.5, from: 2 * .pi - 1.05, to: 2 * .pi)
        p.addPath(ring, transform: tilt)
    }

    static let heart = sketch { p in
        p.m(0, 9)
        p.c(-10, -2, -5, 5, -10, 2)
        p.c(0, -4, -10, -9, -2, -9)
        p.c(10, -2, 2, -9, 10, -9)
        p.c(0, 9, 10, 2, 5, 5)
        p.m(-7.5, -2.5); p.q(-4.5, -6.5, -7.5, -6)
    }

    static let iceCream = sketch { p in
        p.m(-7, 0); p.l(0, 20); p.l(7, 0)
        p.m(-5.25, 5); p.l(2.8, 12)
        p.m(5.25, 5); p.l(-2.8, 12)
        p.arc(0, -6, 8, from: 150, to: 390)
        p.m(-8, -2); p.q(-2.7, -1, -6, 3); p.q(2.7, -1, 0, 3); p.q(8, -2, 6, 3)
        p.circle(1, -16.5, 2.2)
        p.m(1.5, -18.5); p.q(4, -22, 2, -21.5)
    }

    static let donut = sketch { p in
        p.circle(0, 0, 11)
        p.circle(0, 0, 3.5)
        p.wavyCircle(0, 0, r: 8, amplitude: 1.2, waves: 7)
        p.m(-5, -3.5); p.l(-3.5, -5)
        p.m(4, -4.5); p.l(5.5, -2.5)
        p.m(-5.5, 2.5); p.l(-5, 4.5)
        p.m(2.5, 5); p.l(4.5, 5)
        p.m(0, -6.5); p.l(1.5, -5.5)
    }

    static let cat = sketch { p in
        p.m(-11, -3)
        p.l(-10, -14); p.l(-4, -8)
        p.q(4, -8, 0, -9.5)
        p.l(10, -14); p.l(11, -3)
        p.c(-11, -3, 12, 11, -12, 11)
        p.m(-6.5, -1); p.q(-2.5, -1, -4.5, -3.5)
        p.m(2.5, -1); p.q(6.5, -1, 4.5, -3.5)
        p.m(-1, 1.5); p.l(1, 1.5); p.l(0, 2.7); p.close()
        p.m(0, 2.7); p.q(-3, 4, -1, 5)
        p.m(0, 2.7); p.q(3, 4, 1, 5)
        p.m(-7, 2); p.l(-15, 0.5)
        p.m(-7, 4); p.l(-15, 5)
        p.m(7, 2); p.l(15, 0.5)
        p.m(7, 4); p.l(15, 5)
    }

    static let lightbulb = sketch { p in
        p.arc(0, -4, 9, from: 130, to: 410)
        p.l(4, 8); p.l(-4, 8); p.l(-5.8, 2.9)
        p.m(-4, 10.5); p.l(4, 10.5)
        p.m(-3, 13); p.l(3, 13)
        p.m(-2, 7); p.l(-2, 2); p.l(-1, -1); p.l(0, 2); p.l(1, -1); p.l(2, 2); p.l(2, 7)
        p.m(0, -16); p.l(0, -19.5)
        p.m(-9.5, -12.5); p.l(-12, -15)
        p.m(9.5, -12.5); p.l(12, -15)
        p.m(-13, -4); p.l(-16.5, -4)
        p.m(13, -4); p.l(16.5, -4)
    }

    static let umbrella = sketch { p in
        p.arc(0, 0, 15, from: 180, to: 360)
        p.q(7.5, 0, 11.25, -3)
        p.q(0, 0, 3.75, -3)
        p.q(-7.5, 0, -3.75, -3)
        p.q(-15, 0, -11.25, -3)
        p.m(0, -15); p.q(-7.5, 0, -6, -9)
        p.m(0, -15); p.q(7.5, 0, 6, -9)
        p.m(0, -15); p.l(0, -17.5)
        p.m(0, 0); p.l(0, 13)
        p.arc(-2.75, 13, 2.75, from: 0, to: 180)
    }

    static let paperPlane = sketch { p in
        p.m(-12, 1); p.l(15, -9); p.l(4, 9); p.l(0, 3); p.close()
        p.m(0, 3); p.l(15, -9)
        p.m(0, 3); p.l(0.5, 8.5); p.l(2.5, 6.5)
        p.m(-15, 5); p.l(-17, 6)
        p.m(-20.5, 7.5); p.l(-22.5, 9)
        p.m(-25.5, 11); p.l(-27, 13)
    }

    static let coffee = sketch { p in
        p.m(-9, -3); p.l(9, -3); p.l(7, 10); p.q(-7, 10, 0, 12); p.close()
        p.m(8.5, 0); p.c(7.5, 7, 15, -1, 14, 7)
        p.m(-13, 12.5); p.q(13, 12.5, 0, 16.5)
        p.m(-3, -6); p.q(-3, -11, -6, -8.5); p.q(-3, -16, 0, -13.5)
        p.m(3, -6); p.q(3, -11, 0, -8.5); p.q(3, -16, 6, -13.5)
    }

    static let sailboat = sketch { p in
        p.m(-15, 4); p.l(15, 4); p.l(10, 11); p.l(-10, 11); p.close()
        p.m(0, 4); p.l(0, -18)
        p.m(1.5, -15); p.q(13, 1, 12, -8); p.l(1.5, 1)
        p.m(-1.5, -11); p.q(-10, 1, -10, -4); p.l(-1.5, 1)
        p.m(0, -18); p.l(5, -16.5); p.l(0, -15)
        p.wave(-16, 15, width: 32, humps: 4, height: 2.5)
    }

    static let fish = sketch { p in
        p.m(-12, 0); p.q(8, 0, -2, -11); p.q(-12, 0, -2, 11)
        p.m(8, 0); p.l(15, -6); p.q(15, 6, 12.5, 0); p.close()
        p.circle(-6.5, -1.5, 1)
        p.m(-3, -4.5); p.q(-3, 4.5, -0.5, 0)
        p.m(1, -2); p.q(4, 0, 3, -1)
        p.circle(-16, -6, 1.5)
        p.circle(-18.5, -11, 1)
    }

    static let mushroom = sketch { p in
        p.m(-14, 2); p.c(14, 2, -14, -18, 14, -18); p.q(-14, 2, 0, 6)
        p.m(-5, 4); p.l(-6, 13); p.q(6, 13, 0, 15); p.l(5, 4)
        p.circle(-6, -5, 2.5)
        p.circle(4, -8, 3)
        p.circle(8.5, -1.5, 1.4)
        p.m(-16, 15); p.l(16, 15)
        p.m(-12, 15); p.l(-11, 12)
        p.m(11, 15); p.l(12.5, 12)
    }

    static let balloon = sketch { p in
        p.oval(0, -4, width: 18, height: 22)
        p.m(-1.6, 7); p.l(1.6, 7); p.l(0, 9.5); p.close()
        p.m(0, 9.5); p.c(0, 22, -5, 13, 5, 17)
        p.m(-5, -9); p.q(-2, -12, -5, -12)
    }

    static let moon = sketch { p in
        p.arc(0, 0, 12, from: 60, to: 300)
        p.q(6, 10.4, -5, 0)
        p.star(12, -10, 3.5)
        p.circle(14, 4, 1)
        p.circle(-14, -12, 1.2)
    }

    static let gift = sketch { p in
        p.m(-10, -2); p.l(-10, 12); p.l(10, 12); p.l(10, -2)
        p.m(-12, -7); p.l(12, -7); p.l(12, -2); p.l(-12, -2); p.close()
        p.m(-2, -7); p.l(-2, 12)
        p.m(2, -7); p.l(2, 12)
        p.m(0, -7); p.c(0, -7, -10, -16, -12, -6)
        p.m(0, -7); p.c(0, -7, 10, -16, 12, -6)
    }

    static let leaf = sketch { p in
        p.m(-11, 10); p.q(12, -12, -12, -9); p.q(-11, 10, 9, 9)
        p.m(-15, 14); p.l(8, -10)
        p.m(-6, 5); p.l(-8, -1)
        p.m(-1, 0); p.l(-3, -6)
        p.m(-3.5, 2.5); p.l(2.5, 4.5)
        p.m(2.5, -3.5); p.l(7.5, -1.5)
    }

    static let pencil = sketch { p in
        p.m(-13, -3.5); p.l(8, -3.5); p.l(16, 0); p.l(8, 3.5); p.l(-13, 3.5)
        p.q(-13, -3.5, -16, 0)
        p.m(-9, -3.5); p.l(-9, 3.5)
        p.m(8, -3.5); p.l(8, 3.5)
        p.m(12.5, -1.5); p.l(12.5, 1.5)
        p.m(-6, 0); p.l(5, 0)
        p.wave(-2, 12, width: 18, humps: 3, height: 2.5)
    }

    static let checklist = sketch { p in
        p.addRoundedRect(in: CGRect(x: -10, y: -13, width: 20, height: 27), cornerSize: CGSize(width: 2.5, height: 2.5))
        p.m(-4, -13); p.l(-4, -15.5); p.l(4, -15.5); p.l(4, -13)
        p.m(-6.5, -6); p.l(-5, -4.5); p.l(-2, -8)
        p.m(0.5, -6); p.l(6, -6)
        p.m(-6.5, 1); p.l(-5, 2.5); p.l(-2, -1)
        p.m(0.5, 1); p.l(6, 1)
        p.addRect(CGRect(x: -6.5, y: 6, width: 4, height: 4))
        p.m(0.5, 8); p.l(6, 8)
    }

    static let alarmClock = sketch { p in
        p.circle(0, 2, 11)
        p.m(0, 2); p.l(0, -4.5)
        p.m(0, 2); p.l(4.5, 4)
        p.m(-12, -5); p.q(-5, -11, -13, -13); p.close()
        p.m(12, -5); p.q(5, -11, 13, -13); p.close()
        p.m(-7, 11); p.l(-9, 15)
        p.m(7, 11); p.l(9, 15)
        p.m(0, -9); p.l(0, -11)
        p.m(-2.5, -11); p.l(2.5, -11)
    }

    static let cloud = sketch { p in
        p.m(-14, 6)
        p.q(-12, -2, -19, 0)
        p.q(-1, -7, -9, -12)
        p.q(11, -3, 6, -14)
        p.q(14, 6, 21, -1)
        p.close()
        p.m(-6, 12); p.l(-7.5, 15.5)
        p.m(1, 12); p.l(-0.5, 15.5)
        p.m(8, 12); p.l(6.5, 15.5)
    }

    static let snail = sketch { p in
        p.circle(3, -3, 9)
        p.spiral(3, -3, 7, turns: 2)
        p.m(17, 3.5); p.q(13, 6, 16, 6); p.l(-8, 6)
        p.c(-11, -3, -12, 6, -14, -3)
        p.q(-5.6, 0, -7, -3)
        p.circle(-10.5, 1, 0.7)
        p.m(-12, -2.5); p.l(-14.5, -10); p.circle(-14.8, -11, 1)
        p.m(-10, -3); p.l(-8.5, -10.5); p.circle(-8.3, -11.5, 1)
    }

    static let cactus = sketch { p in
        p.m(-4, 11); p.l(-4, -11); p.q(4, -11, 0, -16); p.l(4, 11)
        p.m(-4, 3); p.l(-8, 3); p.q(-11, 0, -11, 3); p.l(-11, -5); p.q(-7.5, -5, -9.25, -7); p.l(-7.5, 0); p.l(-4, 0)
        p.m(4, -1); p.l(8, -1); p.q(11, -4, 11, -1); p.l(11, -9); p.q(7.5, -9, 9.25, -11); p.l(7.5, -4); p.l(4, -4)
        p.m(-8, 11); p.l(8, 11); p.l(6, 19); p.l(-6, 19); p.close()
        p.m(-1.5, -8); p.l(-1.5, -6)
        p.m(1.5, -2); p.l(1.5, 0)
        p.m(-1.5, 5); p.l(-1.5, 7)
    }

    static let flower = sketch { p in
        p.circle(0, -6, 3)
        for i in 0..<6 {
            let petal = Path(ellipseIn: CGRect(x: -3, y: -12, width: 6, height: 8.5))
            p.addPath(petal, transform: CGAffineTransform(rotationAngle: CGFloat(i) * .pi / 3)
                .concatenating(CGAffineTransform(translationX: 0, y: -6)))
        }
        p.m(0, 3.5); p.q(-1, 19, 2, 11)
        p.m(0.5, 13); p.q(8, 8, 6, 14); p.q(0.5, 13, 3, 9)
    }

    static let music = sketch { p in
        p.oval(-6, 8, width: 7, height: 5)
        p.oval(7, 5, width: 7, height: 5)
        p.m(-2.5, 8); p.l(-2.5, -10)
        p.m(10.5, 5); p.l(10.5, -13)
        p.m(-2.5, -10); p.l(10.5, -13)
        p.m(-2.5, -6.5); p.l(10.5, -9.5)
    }

    static let camera = sketch { p in
        p.addRoundedRect(in: CGRect(x: -14, y: -7, width: 28, height: 19), cornerSize: CGSize(width: 3, height: 3))
        p.m(-6, -7); p.l(-4, -11); p.l(4, -11); p.l(6, -7)
        p.circle(0, 2.5, 6)
        p.circle(0, 2.5, 3)
        p.m(-11, -3.5); p.l(-8, -3.5)
        p.circle(10, -3, 1)
    }

    static let sun = sketch { p in
        p.circle(0, 0, 8)
        for i in 0..<10 {
            let a = CGFloat(i) * .pi / 5
            p.m(11 * cos(a), 11 * sin(a))
            p.l((i.isMultiple(of: 2) ? 16 : 14) * cos(a), (i.isMultiple(of: 2) ? 16 : 14) * sin(a))
        }
        p.circle(-3, -1.5, 0.8)
        p.circle(3, -1.5, 0.8)
        p.m(-3.5, 2.5); p.q(3.5, 2.5, 0, 5.5)
    }

    static let headphones = sketch { p in
        p.arc(0, 2, 13, from: 180, to: 360)
        p.l(13, 4)
        p.m(-13, 2); p.l(-13, 4)
        p.addRoundedRect(in: CGRect(x: -16, y: 3, width: 7, height: 12), cornerSize: CGSize(width: 2.5, height: 2.5))
        p.addRoundedRect(in: CGRect(x: 9, y: 3, width: 7, height: 12), cornerSize: CGSize(width: 2.5, height: 2.5))
        p.m(-9, -7); p.q(9, -7, 0, -12)
    }

    static let dice = sketch { p in
        p.addRoundedRect(in: CGRect(x: -11, y: -11, width: 22, height: 22), cornerSize: CGSize(width: 4, height: 4))
        p.circle(-5.5, -5.5, 1.5)
        p.circle(0, 0, 1.5)
        p.circle(5.5, 5.5, 1.5)
        p.circle(5.5, -5.5, 1.5)
        p.circle(-5.5, 5.5, 1.5)
    }

    private static func sketch(_ draw: (inout Path) -> Void) -> Path {
        var path = Path()
        draw(&path)
        return path
    }
}

/// Short pen-plotter style helpers for the drawings above. Angles are in degrees and,
/// with y pointing down, increasing angles run clockwise on screen.
private extension Path {
    mutating func m(_ x: CGFloat, _ y: CGFloat) { move(to: CGPoint(x: x, y: y)) }
    mutating func l(_ x: CGFloat, _ y: CGFloat) { addLine(to: CGPoint(x: x, y: y)) }
    mutating func close() { closeSubpath() }

    mutating func q(_ x: CGFloat, _ y: CGFloat, _ cx: CGFloat, _ cy: CGFloat) {
        addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: cx, y: cy))
    }

    mutating func c(_ x: CGFloat, _ y: CGFloat,
                    _ c1x: CGFloat, _ c1y: CGFloat, _ c2x: CGFloat, _ c2y: CGFloat) {
        addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: c1x, y: c1y), control2: CGPoint(x: c2x, y: c2y))
    }

    mutating func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
        addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    mutating func oval(_ x: CGFloat, _ y: CGFloat, width: CGFloat, height: CGFloat) {
        addEllipse(in: CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height))
    }

    mutating func arc(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, from start: Double, to end: Double) {
        let a = start * .pi / 180
        m(x + r * cos(a), y + r * sin(a))
        addArc(center: CGPoint(x: x, y: y), radius: r,
               startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
    }

    /// Part of an axis-aligned ellipse around the origin, angles in radians.
    mutating func ellipseArc(rx: CGFloat, ry: CGFloat, from start: CGFloat, to end: CGFloat) {
        let steps = 24
        for i in 0...steps {
            let t = start + (end - start) * CGFloat(i) / CGFloat(steps)
            let point = CGPoint(x: rx * cos(t), y: ry * sin(t))
            if i == 0 { move(to: point) } else { addLine(to: point) }
        }
    }

    mutating func star(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
        for i in 0..<10 {
            let radius = i.isMultiple(of: 2) ? r : r * 0.45
            let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
            let point = CGPoint(x: x + radius * cos(a), y: y + radius * sin(a))
            if i == 0 { move(to: point) } else { addLine(to: point) }
        }
        closeSubpath()
    }

    /// A four-pointed twinkle with concave sides.
    mutating func sparkle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
        m(x, y - r)
        q(x + r, y, x, y)
        q(x, y + r, x, y)
        q(x - r, y, x, y)
        q(x, y - r, x, y)
    }

    mutating func spiral(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, turns: CGFloat) {
        let steps = Int(turns * 28)
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let a = t * turns * 2 * .pi
            let point = CGPoint(x: x + r * t * cos(a), y: y + r * t * sin(a))
            if i == 0 { move(to: point) } else { addLine(to: point) }
        }
    }

    mutating func wavyCircle(_ x: CGFloat, _ y: CGFloat, r: CGFloat, amplitude: CGFloat, waves: Int) {
        let steps = waves * 12
        for i in 0...steps {
            let a = CGFloat(i) / CGFloat(steps) * 2 * .pi
            let radius = r + amplitude * sin(CGFloat(waves) * a)
            let point = CGPoint(x: x + radius * cos(a), y: y + radius * sin(a))
            if i == 0 { move(to: point) } else { addLine(to: point) }
        }
    }

    /// A row of gentle humps starting at (x, y).
    mutating func wave(_ x: CGFloat, _ y: CGFloat, width: CGFloat, humps: Int, height: CGFloat) {
        let step = width / CGFloat(humps)
        m(x, y)
        for i in 0..<humps {
            let x0 = x + CGFloat(i) * step
            q(x0 + step, y, x0 + step / 2, i.isMultiple(of: 2) ? y - height * 2 : y + height * 2)
        }
    }
}
