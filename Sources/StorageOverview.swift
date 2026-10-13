import SwiftUI
import AppKit

// MARK: Categories

enum Tier { case safe, look }

struct SpaceCategory: Identifiable {
    let id: String, title: String, icon: Glyph, why: String
    let tier: Tier
    let paths: [URL]

    static let home = FileManager.default.homeDirectoryForCurrentUser
    private static func h(_ p: String) -> URL { home.appendingPathComponent(p) }

    static let all: [SpaceCategory] = [
        SpaceCategory(id: "caches", title: "Caches", icon: .cache, why: "Temporary data apps rebuild by themselves.", tier: .safe, paths: [h("Library/Caches")]),
        SpaceCategory(id: "logs", title: "Logs", icon: .log, why: "Old diagnostic reports and logs.", tier: .safe, paths: [h("Library/Logs")]),
        SpaceCategory(id: "derived", title: "Xcode build files", icon: .build, why: "Rebuilt automatically on the next build.", tier: .safe, paths: [h("Library/Developer/Xcode/DerivedData")]),
        SpaceCategory(id: "downloads", title: "Downloads", icon: .download, why: "Installers and files you may no longer need.", tier: .look, paths: [h("Downloads")]),
        SpaceCategory(id: "sims", title: "Simulators & device support", icon: .device, why: "Large, but can be downloaded again.", tier: .look,
                 paths: [h("Library/Developer/CoreSimulator"), h("Library/Developer/Xcode/iOS DeviceSupport")]),
        SpaceCategory(id: "archives", title: "Xcode archives", icon: .archive, why: "Old app builds. Keep any you still ship.", tier: .look, paths: [h("Library/Developer/Xcode/Archives")]),
    ]

    var tint: Color { tier == .safe ? .green : .orange }
}

enum Palette {
    static func color(for name: String) -> Color {
        switch name {
        case "Library": return Theme.violet
        case "Downloads": return Theme.amber
        case "Documents": return hue(0.35, 0.65, 1.0)
        case "Desktop": return Theme.cyan
        case "Movies": return Theme.pink
        case "Pictures": return hue(1, 0.45, 0.35)
        case "Music": return hue(0.45, 0.5, 1)
        case "Applications": return hue(0.3, 0.6, 1)
        default:
            let others: [Color] = [hue(0.2, 0.8, 0.8), hue(0.75, 0.55, 1), hue(0.95, 0.8, 0.3), hue(0.4, 0.85, 0.5), hue(0.95, 0.5, 0.75)]
            return others[name.unicodeScalars.reduce(0) { ($0 &+ Int($1.value)) } % others.count]
        }
    }

    static func fileStyle(_ url: URL) -> (Glyph, Color) {
        switch url.pathExtension.lowercased() {
        case "mov", "mp4", "m4v", "mkv", "avi": return (.film, Theme.pink)
        case "jpg", "jpeg", "png", "heic", "raw", "dng", "tiff", "psd": return (.photo, Color(red: 1, green: 0.45, blue: 0.35))
        case "zip", "dmg", "pkg", "iso", "xip", "tar", "gz", "rar", "7z": return (.box, Theme.amber)
        case "mp3", "wav", "m4a", "flac", "aiff": return (.music, Color(red: 0.45, green: 0.5, blue: 1))
        case "pdf", "doc", "docx", "pages", "key", "ppt", "pptx", "xls", "xlsx", "numbers": return (.doc, Theme.cyan)
        case "app": return (.app, Theme.cyan)
        default: return (.file, Theme.ink.opacity(0.5))
        }
    }
}

// MARK: Treemap

struct Tile: Identifiable { let item: SizedItem; let rect: CGRect; var id: URL { item.url } }

enum Treemap {
    /// Squarified treemap layout (Bruls, Huizing, van Wijk).
    static func layout(_ items: [SizedItem], in bounds: CGRect) -> [Tile] {
        let items = items.filter { $0.size > 0 }
        let total = Double(items.reduce(0) { $0 + $1.size })
        guard total > 0, bounds.width > 0, bounds.height > 0 else { return [] }
        let scale = Double(bounds.width * bounds.height) / total
        var rest = items.map { ($0, Double($0.size) * scale) }
        var r = bounds
        var out: [Tile] = []
        func worst(_ row: [(SizedItem, Double)], _ w: Double) -> Double {
            let s = row.reduce(0) { $0 + $1.1 }
            guard s > 0, let mx = row.map(\.1).max(), let mn = row.map(\.1).min(), mn > 0 else { return .infinity }
            return max(w * w * mx / (s * s), s * s / (w * w * mn))
        }
        while !rest.isEmpty {
            let w = Double(min(r.width, r.height))
            var row = [rest.removeFirst()]
            while let next = rest.first, worst(row + [next], w) <= worst(row, w) { row.append(rest.removeFirst()) }
            let s = row.reduce(0) { $0 + $1.1 }
            if r.width >= r.height {
                let colW = CGFloat(s) / r.height
                var y = r.minY
                for (it, a) in row { let h = CGFloat(a) / colW; out.append(Tile(item: it, rect: CGRect(x: r.minX, y: y, width: colW, height: h))); y += h }
                r = CGRect(x: r.minX + colW, y: r.minY, width: max(0, r.width - colW), height: r.height)
            } else {
                let rowH = CGFloat(s) / r.width
                var x = r.minX
                for (it, a) in row { let wd = CGFloat(a) / rowH; out.append(Tile(item: it, rect: CGRect(x: x, y: r.minY, width: wd, height: rowH))); x += wd }
                r = CGRect(x: r.minX, y: r.minY + rowH, width: r.width, height: max(0, r.height - rowH))
            }
        }
        return out
    }
}

struct TreemapView: View {
    let items: [SizedItem]
    @Binding var selected: URL?
    @Binding var hovered: URL?

    var body: some View {
        GeometryReader { geo in
            let tiles = Treemap.layout(items, in: CGRect(origin: .zero, size: geo.size))
            ZStack {
                ForEach(tiles) { t in
                    let c = Palette.color(for: t.item.url.lastPathComponent)
                    let isSel = selected == t.item.url
                    let isHover = hovered == t.item.url
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(c.opacity(isHover ? 0.95 : 0.78))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Theme.ink.opacity(isSel ? 0.95 : 0), lineWidth: 2.5))
                        .overlay(alignment: .topLeading) {
                            if t.rect.width > 80, t.rect.height > 48 {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(t.item.url.lastPathComponent).font(Typo.ui(13, .semibold)).lineLimit(1)
                                    Text(formatBytes(t.item.size)).font(Typo.ui(11)).opacity(0.85)
                                }
                                .foregroundStyle(Theme.onAccent).padding(10)
                            }
                        }
                        .frame(width: max(0, t.rect.width - 4), height: max(0, t.rect.height - 4))
                        .position(x: t.rect.midX, y: t.rect.midY)
                        .onHover { hovered = $0 ? t.item.url : (hovered == t.item.url ? nil : hovered) }
                        .onTapGesture { selected = t.item.url }
                }
            }
            .animation(.snappy(duration: 0.15), value: hovered)
        }
    }
}

// MARK: Overview

struct OverviewView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var scanner: StorageScanner
    @ObservedObject var finder: DuplicateFinder
    @State private var ticked: Set<String> = Set(SpaceCategory.all.filter { $0.tier == .safe }.map(\.id))
    @State private var treeSel: URL?
    @State private var treeHover: URL?

    private func size(_ id: String) -> Int64 { scanner.categorySizes[id] ?? 0 }
    private var safeBytes: Int64 { SpaceCategory.all.filter { $0.tier == .safe }.reduce(0) { $0 + size($1.id) } }
    private var lookBytes: Int64 { SpaceCategory.all.filter { $0.tier == .look }.reduce(0) { $0 + size($1.id) } }
    private var tickedBytes: Int64 { SpaceCategory.all.filter { ticked.contains($0.id) }.reduce(0) { $0 + size($1.id) } }
    private var disk: (total: Int64, free: Int64) {
        let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        return (Int64(v?.volumeTotalCapacity ?? 0), v?.volumeAvailableCapacityForImportantUsage ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Overview", subtitle: scanner.scanning ? "Scanning. Showing what has been found so far; sizes keep growing."
                         : scanner.partial ? "Last scan did not finish. Showing partial results. Rescan to complete."
                         : scanner.lastScan.map { "Last scanned \(ago($0)). Results are remembered." } ?? "Scan your Mac to see where the space went.") {
                HStack(spacing: 10) {
                    if scanner.scanning { ProgressView().controlSize(.small); Text("\(scanner.scanned) files…").foregroundStyle(Theme.muted) }
                    Button(scanner.hasResult ? "Rescan" : "Scan Mac") { scanner.scan() }
                        .buttonStyle(GhostButtonStyle()).disabled(scanner.scanning)
                }
            }
            ScrollView {
                VStack(spacing: 16) {
                    hero
                    HStack(alignment: .top, spacing: 16) { safeTile; lookTile }
                    treemapTile
                    ToolsBar()
                }
            }
            .scrollIndicators(.hidden)
        }
        .onAppear { if scanner.categorySizes.isEmpty { scanner.refreshCategories() } }
    }

    // Hero: donut of the whole disk + the one number that matters.
    private var hero: some View {
        let d = disk
        let total = Double(max(1, d.total))
        let used = max(1, d.total - d.free)
        let kept = max(0, used - safeBytes - lookBytes)
        return HStack(spacing: 34) {
            ZStack {
                Ring(parts: [(Double(kept) / total, Theme.kept), (Double(safeBytes) / total, Theme.mint), (Double(lookBytes) / total, Theme.amber)], lineWidth: 16)
                VStack(spacing: 0) {
                    Text("FREE").font(Typo.ui(10, .bold)).foregroundStyle(Theme.faint)
                    Text(formatBytes(d.free)).font(Typo.display(26, .bold)).monospacedDigit()
                        .contentTransition(.numericText())
                    Text("of \(formatBytes(d.total))").font(Typo.ui(11)).foregroundStyle(Theme.muted)
                }
            }
            .frame(width: 190, height: 190)
            VStack(alignment: .leading, spacing: 10) {
                Text("SELECTED").font(Typo.ui(11, .bold)).foregroundStyle(Theme.muted).tracking(1.4)
                Text(formatBytes(tickedBytes))
                    .font(Typo.display(56, .semibold)).monospacedDigit()
                    .foregroundStyle(.primary).contentTransition(.numericText())
                    .animation(.snappy, value: tickedBytes)
                Text("Caches, logs and build files from your Library. They move to the Trash; the space comes back when you empty it.").foregroundStyle(Theme.muted).frame(maxWidth: 440, alignment: .leading)
                HStack(spacing: 12) {
                    Button { clearTicked() } label: { Text("Move selected to Trash") }
                        .buttonStyle(GlowButtonStyle()).disabled(tickedBytes == 0)
                    Button { model.tab = .copy } label: { HStack(spacing: 7) { Icon(glyph: .nas, size: 15); Text("Move files to NAS") } }
                        .buttonStyle(GhostButtonStyle())
                }
                HStack(spacing: 18) {
                    legend(Theme.kept, "Kept", kept); legend(Theme.mint, "Safe", safeBytes); legend(Theme.amber, "Worth a look", lookBytes)
                }.padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .bento(24)
    }

    private func legend(_ c: Color, _ t: String, _ b: Int64) -> some View {
        HStack(spacing: 6) {
            Circle().fill(c).frame(width: 8, height: 8)
            Text(t).font(Typo.ui(11)).foregroundStyle(Theme.muted)
            Text(formatBytes(b)).font(Typo.ui(11, .bold)).monospacedDigit()
        }
    }

    private var safeTile: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Safe to clear").font(Typo.display(19, .bold)); Text("rebuilt by the apps that made them").font(Typo.ui(12)).foregroundStyle(Theme.muted) }
            ForEach(SpaceCategory.all.filter { $0.tier == .safe }) { c in
                categoryRow(c) {
                    Toggle("", isOn: Binding(get: { ticked.contains(c.id) }, set: { on in if on { ticked.insert(c.id) } else { ticked.remove(c.id) } }))
                        .toggleStyle(RoundCheckStyle(tint: Theme.mint)).labelsHidden()
                }
            }
        }.bento()
    }

    private var lookTile: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Worth a look").font(Typo.display(19, .bold)); Text("check before you decide").font(Typo.ui(12)).foregroundStyle(Theme.muted) }
            ForEach(SpaceCategory.all.filter { $0.tier == .look }) { c in
                categoryRow(c) { Button("Review") { review(c) }.buttonStyle(GhostButtonStyle()) }
            }
            HStack(spacing: 12) {
                icon(.duplicates, Theme.amber)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Duplicates")
                    Text("Identical big files stored twice").font(Typo.ui(11)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Text(finder.hasResult ? formatBytes(finder.totalWasted) : "not scanned").foregroundStyle(Theme.muted).monospacedDigit()
                Button("Review") { model.tab = .duplicates }.buttonStyle(GhostButtonStyle())
            }
        }.bento()
    }

    private func icon(_ name: Glyph, _ c: Color) -> some View {
        Icon(glyph: name, size: 18).foregroundStyle(c)
            .frame(width: 34, height: 34).background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(c.opacity(0.16)))
    }

    private func categoryRow<A: View>(_ c: SpaceCategory, @ViewBuilder action: () -> A) -> some View {
        HStack(spacing: 12) {
            icon(c.icon, c.tier == .safe ? Theme.mint : Theme.amber)
            VStack(alignment: .leading, spacing: 1) {
                Text(c.title)
                Text(c.why).font(Typo.ui(11)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(scanner.categorySizes[c.id] == nil ? "…" : formatBytes(size(c.id)))
                .font(Typo.ui(13, .semibold)).foregroundStyle(Theme.ink.opacity(0.85)).monospacedDigit()
            action()
        }
    }

    private var treemapTile: some View {
        let top = Array(scanner.topLevel.prefix(24))
        let total = max(1, scanner.topLevel.reduce(0) { $0 + $1.size })
        let focus = (treeHover ?? treeSel).flatMap { u in scanner.topLevel.first { $0.url == u } }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your home folder, by size").font(Typo.display(19, .bold))
                Spacer()
                if let f = focus {
                    Circle().fill(Palette.color(for: f.url.lastPathComponent)).frame(width: 9, height: 9)
                    Text(f.url.lastPathComponent).font(Typo.ui(13, .semibold))
                    Text("\(formatBytes(f.size)) · \(Int(Double(f.size) / Double(total) * 100))%").foregroundStyle(Theme.muted)
                } else { Text("Hover a block").foregroundStyle(Theme.faint) }
            }
            if top.isEmpty {
                Text("Scan to draw the map.").foregroundStyle(Theme.muted).frame(maxWidth: .infinity, minHeight: 120)
            } else {
                TreemapView(items: top, selected: $treeSel, hovered: $treeHover).frame(height: 280)
            }
            if let u = treeSel {
                HStack {
                    Text("Selected: \(u.lastPathComponent)").font(Typo.ui(13, .semibold))
                    Spacer()
                    Button("Browse") { model.browser.load(u); model.tab = .copy }.buttonStyle(GhostButtonStyle())
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([u]) }.buttonStyle(GhostButtonStyle())
                    Button("Add to NAS list") { model.add([u]); model.tab = .copy }.buttonStyle(GhostButtonStyle())
                }
            }
        }.bento()
    }

    private func review(_ c: SpaceCategory) {
        if let p = c.paths.first(where: { FileManager.default.fileExists(atPath: $0.path) }) { model.browser.load(p); model.tab = .copy }
    }

    private func clearTicked() {
        var urls: [URL] = []
        var lines: [String] = []
        for c in SpaceCategory.all where ticked.contains(c.id) {
            for p in c.paths {
                // Skip a category root that is a symlink pointing outside the home folder.
                guard isInsideHome(p), p.resolvingSymlinksInPath().path.hasPrefix(NSHomeDirectory() + "/") else { continue }
                urls += ((try? FileManager.default.contentsOfDirectory(at: p, includingPropertiesForKeys: nil)) ?? [])
            }
            lines.append("• \(c.title) — \(formatBytes(size(c.id)))")
        }
        model.trash(urls, detail: "This moves the contents of:\n" + lines.joined(separator: "\n"))
        scanner.refreshCategories()
    }
}

// MARK: Biggest

struct BiggestView: View {
    enum Kind: String, CaseIterable { case files = "Files", folders = "Folders" }
    @EnvironmentObject var model: AppModel
    @ObservedObject var scanner: StorageScanner
    @State private var kind = Kind.files
    @State private var selection = Set<URL>()
    @State private var preview: URL?
    private func targets(_ u: URL) -> [URL] { selection.contains(u) ? Array(selection) : [u] }

    var body: some View {
        let items = kind == .files ? scanner.files : scanner.folders
        let top = Double(max(1, items.first?.size ?? 1))
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Biggest", subtitle: scanner.scanning ? "Scanning… \(scanner.scanned) files so far. Showing the biggest found yet." : "The heaviest things on your Mac, largest first.") {
                Segmented(options: Kind.allCases, label: { $0.rawValue }, selection: $kind)
            }
            if !scanner.hasResult {
                VStack(spacing: 12) {
                    Text("Nothing scanned yet.").foregroundStyle(Theme.muted)
                    Button("Scan Mac") { scanner.scan() }.buttonStyle(GlowButtonStyle()).disabled(scanner.scanning)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).bento()
            } else {
                VStack(spacing: 8) {
                    List(items, selection: $selection) { item in
                        let style = kind == .files ? Palette.fileStyle(item.url) : (Glyph.folder, Palette.color(for: item.url.lastPathComponent))
                        let sel = selection.contains(item.url)
                        HStack(spacing: 12) {
                            Icon(glyph: style.0, size: 17).foregroundStyle(sel ? Color.white : style.1)
                                .frame(width: 34, height: 34)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(sel ? Color.white.opacity(0.22) : style.1.opacity(0.16)))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.url.lastPathComponent).lineLimit(1)
                                Text(item.url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                    .font(Typo.ui(11)).foregroundStyle(sel ? Color.white.opacity(0.8) : Theme.faint).lineLimit(1).truncationMode(.head)
                                GeometryReader { g in
                                    RoundedRectangle(cornerRadius: 1.5).fill(sel ? Color.white.opacity(0.8) : style.1.opacity(0.7)).frame(width: max(2, g.size.width * Double(item.size) / top), height: 3)
                                }.frame(height: 3)
                            }
                            Spacer(minLength: 8)
                            Text(formatBytes(item.size)).font(Typo.ui(13, .semibold)).monospacedDigit().foregroundStyle(sel ? Color.white : Theme.ink)
                            Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: { Icon(glyph: .search) }
                                .buttonStyle(IconButtonStyle(tint: sel ? .white : Theme.muted)).help("Show in Finder")
                            Button { model.add(targets(item.url)); model.tab = .copy } label: { Icon(glyph: .plus) }
                                .buttonStyle(IconButtonStyle(tint: sel ? .white : Theme.mint)).help("Add to NAS copy list")
                            Button { model.trash(targets(item.url)) } label: { Icon(glyph: .trash) }
                                .buttonStyle(IconButtonStyle(tint: sel ? .white : Theme.pink)).help("Move to Trash")
                        }
                        .padding(.vertical, 3)
                        .listRowSeparator(.hidden)
                        .contextMenu { Button("Move to Trash", role: .destructive) { model.trash(targets(item.url)) } }
                    }
                    .darkList()
                    .onDeleteCommand { model.trash(Array(selection)) }
                    .spacePreview(selection: selection, items: items.map(\.url), preview: $preview)
                    SelectionBar(selection: selection, clear: { selection = [] })
                }.bento()
            }
        }
    }
}
