import SwiftUI

/// A set of sticker images for a sticker wallpaper style. The images ship in the app's
/// Resources/<folder> (see build.sh).
enum StickerPack {
    /// Rilakkuma, Korilakkuma and Kiiroitori on honey-cream.
    case rilakkuma
    /// Quby on baby blue.
    case quby

    var folder: String {
        switch self {
        case .rilakkuma: "Rilakkuma"
        case .quby: "Quby"
        }
    }

    /// Used instead of the theme's accent (Soft Pink keeps its rose).
    var accent: NSColor {
        switch self {
        case .rilakkuma: NSColor(srgbRed: 0.80, green: 0.52, blue: 0.24, alpha: 1)
        case .quby: NSColor(srgbRed: 0.93, green: 0.45, blue: 0.54, alpha: 1)
        }
    }

    func background(theme: Theme, dark: Bool) -> [Color] {
        if theme == .pink {
            return [Color(red: 1.0, green: 0.86, blue: 0.90), Color(red: 0.99, green: 0.91, blue: 0.93)]
        }
        switch (self, dark) {
        case (.rilakkuma, false):
            return [Color(red: 1.0, green: 0.95, blue: 0.86), Color(red: 0.98, green: 0.88, blue: 0.71)]
        case (.rilakkuma, true):
            return [Color(red: 0.19, green: 0.13, blue: 0.09), Color(red: 0.10, green: 0.07, blue: 0.05)]
        case (.quby, false):
            return [Color(red: 0.87, green: 0.94, blue: 1.0), Color(red: 0.95, green: 0.97, blue: 1.0)]
        case (.quby, true):
            return [Color(red: 0.11, green: 0.13, blue: 0.19), Color(red: 0.06, green: 0.07, blue: 0.10)]
        }
    }

    fileprivate var tile: StickerTile {
        switch self {
        case .rilakkuma: StickerTile.rilakkuma
        case .quby: StickerTile.quby
        }
    }
}

extension WindowStyle {
    /// The sticker pack this style shows, if it's a sticker style.
    var stickerPack: StickerPack? {
        switch self {
        case .rilakkuma: .rilakkuma
        case .quby: .quby
        default: nil
        }
    }
}

/// Sticker wallpaper: a pack's stickers scattered over a soft gradient with white polka dots.
struct StickerBackground: View {
    let pack: StickerPack
    let shape: UnevenRoundedRectangle
    let theme: Theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        let tile = pack.tile
        ZStack {
            shape.fill(LinearGradient(colors: pack.background(theme: theme, dark: dark),
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            Canvas { context, size in
                let images = tile.images.map { context.resolve(Image(nsImage: $0).interpolation(.high)) }
                let dot = Path(ellipseIn: CGRect(x: -4, y: -4, width: 8, height: 8))
                let dotColor = dark ? Color(red: 0.9, green: 0.9, blue: 1.0).opacity(0.08) : Color.white.opacity(0.85)
                // The images are drawn faint, so task text stays easy to read on top.
                var faint = context
                faint.opacity = dark ? 0.09 : 0.12
                for origin in TileScatter.origins(tile: tile.size, covering: size) {
                    for placement in tile.scatter.fillers {
                        context.fill(dot.applying(placement.transform).offsetBy(dx: origin.x, dy: origin.y),
                                     with: .color(dotColor))
                    }
                    for placement in tile.scatter.motifs {
                        var c = faint
                        c.translateBy(x: origin.x, y: origin.y)
                        c.concatenate(placement.transform)
                        let size = tile.sizes[placement.index]
                        c.draw(images[placement.index],
                               in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
                    }
                }
            }
            .clipShape(shape)
        }
        .allowsHitTesting(false)
    }
}

/// One pack's images, loaded once, and where they sit on the repeating tile.
private struct StickerTile {
    static let rilakkuma = StickerTile(folder: StickerPack.rilakkuma.folder, seed: 11)
    static let quby = StickerTile(folder: StickerPack.quby.folder, seed: 23)

    /// Four stickers to a row, as many rows as it takes to show each one.
    let size: CGSize
    let images: [NSImage]
    /// Display size in points: the images are about 2.5× the size they should appear.
    let sizes: [CGSize]
    let scatter: TileScatter

    private init(folder: String, seed: UInt64) {
        var images: [NSImage] = []
        if let url = Bundle.main.resourceURL?.appendingPathComponent(folder),
           let files = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
            let sorted = files.filter { $0.pathExtension == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            // A fixed shuffle, so similar stickers from the same row of the sheet are spread out.
            let order = sorted.indices.sorted { ($0 * 7) % sorted.count < ($1 * 7) % sorted.count }
            images = order.compactMap { NSImage(contentsOf: sorted[$0]) }
        }
        self.images = images
        sizes = images.map { image in
            let pixels = image.representations.first.map { CGSize(width: $0.pixelsWide, height: $0.pixelsHigh) } ?? image.size
            return CGSize(width: pixels.width * 0.4, height: pixels.height * 0.4)
        }
        let rows = max(1, (images.count + 3) / 4)
        size = CGSize(width: 320, height: CGFloat(rows) * 80)
        scatter = TileScatter(
            size: size, columns: 4, rows: rows, jitter: 8, tilt: 20, scale: 0.9...1.05,
            motifs: sizes.map { Path(CGRect(x: -$0.width / 2, y: -$0.height / 2, width: $0.width, height: $0.height)) },
            fillers: [Path(ellipseIn: CGRect(x: -4, y: -4, width: 8, height: 8))],
            fillerCount: rows * 5, seed: seed
        )
    }
}
