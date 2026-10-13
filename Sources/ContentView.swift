import SwiftUI
import QuickLook
import AppKit

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            HStack(spacing: 0) {
                Rail()
                Group {
                    switch model.tab {
                    case .storage: OverviewView(scanner: model.scanner, finder: model.finder)
                    case .copy: MoveView(browser: model.browser)
                    case .duplicates: DuplicatesView(finder: model.finder)
                    case .biggest: BiggestView(scanner: model.scanner)
                    }
                }
                .padding(.horizontal, 26).padding(.top, 30).padding(.bottom, 22)
                .transition(.opacity)
            }
        }
        .font(Typo.ui(13))
        .preferredColorScheme(model.appearance.scheme)
        .accentColor(Theme.violet).tint(Theme.violet)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { Task { @MainActor in model.add([url]); model.tab = .copy } }
                }
            }
            return true
        }
    }
}

// MARK: Navigation rail

struct Rail: View {
    @EnvironmentObject var model: AppModel
    private func icon(_ t: AppModel.Tab) -> Glyph {
        switch t {
        case .storage: return .overview
        case .copy: return .nas
        case .duplicates: return .duplicates
        case .biggest: return .biggest
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.violet)
                .frame(width: 40, height: 40)
                .overlay(Icon(glyph: .logo, size: 24).foregroundStyle(Theme.onAccent))
                .padding(.bottom, 14)
            ForEach(AppModel.Tab.allCases, id: \.self) { t in
                RailItem(title: t.rawValue, icon: icon(t), selected: model.tab == t) {
                    withAnimation(.snappy(duration: 0.2)) { model.tab = t }
                }
            }
            Spacer()
            Button { model.appearance = model.appearance.next } label: { Icon(glyph: model.appearance.glyph, size: 17) }
                .buttonStyle(IconButtonStyle())
                .help("Appearance: \(model.appearance.label). Click to change.")
                .padding(.bottom, 10)
            VStack(spacing: 5) {
                Circle().fill(model.connected ? Theme.mint : Theme.pink).frame(width: 8, height: 8)
                Text("NAS").font(Typo.ui(10, .semibold)).foregroundStyle(Theme.muted)
            }.padding(.bottom, 6)
        }
        .padding(.top, 40).padding(.bottom, 18).padding(.horizontal, 10)
        .frame(width: 92)
        .background(Theme.rail)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.stroke).frame(width: 1) }
    }
}

struct RailItem: View {
    let title: String
    let icon: Glyph
    let selected: Bool
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Icon(glyph: icon, size: 24)
                    .foregroundStyle(selected ? Theme.violet : Theme.muted)
                Text(title).font(Typo.ui(10, .semibold))
                    .foregroundStyle(selected ? Theme.ink : Theme.muted).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(width: 72, height: 58)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Theme.surface2 : Theme.ink.opacity(hover ? 0.05 : 0)))
            .overlay(alignment: .leading) {
                if selected { Capsule().fill(Theme.violet).frame(width: 3, height: 26).offset(x: -8) }
            }
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: Shared bits

extension View {
    /// Finder-style: select rows, press Space for Quick Look.
    func spacePreview(selection: Set<URL>, items: [URL], preview: Binding<URL?>) -> some View {
        let chosen = items.filter(selection.contains)
        return self.onKeyPress(.space) {
            guard let s = chosen.first else { return .ignored }
            preview.wrappedValue = s
            return .handled
        }
        .quickLookPreview(preview, in: chosen)
    }

    func darkList() -> some View {
        self.listStyle(.plain).scrollContentBackground(.hidden)
    }
}

struct SelectionBar: View {
    @EnvironmentObject var model: AppModel
    let selection: Set<URL>
    let clear: () -> Void
    var body: some View {
        if selection.count > 1 {
            HStack {
                Text("\(selection.count) selected").font(Typo.ui(13, .semibold))
                Spacer()
                Button("Add to copy list") { model.add(Array(selection)); clear() }.buttonStyle(GhostButtonStyle())
                Button("Move to Trash") { model.trash(Array(selection)); clear() }
                    .buttonStyle(GlowButtonStyle(gradient: Theme.warm, glow: Theme.pink))
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface2))
        }
    }
}

struct NASChip: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(model.connected ? Theme.mint : Theme.pink).frame(width: 8, height: 8)
            Text(model.connected ? "NAS · \(model.selectedShare)" : "NAS not connected")
                .font(Typo.ui(13, .medium))
            if model.connected, model.shares.count > 1 {
                Picker("", selection: $model.selectedShare) {
                    ForEach(model.shares, id: \.name) { Text($0.name).tag($0.name) }
                }.labelsHidden().frame(width: 130)
            }
            if !model.connected { Button("Connect") { model.connect() }.buttonStyle(GhostButtonStyle()) }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
    }
}

// MARK: Move to NAS

struct MoveView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var browser: Browser
    @State private var selection = Set<URL>()
    @State private var preview: URL?
    @FocusState private var listFocused: Bool

    private func targets(_ u: URL) -> [URL] { selection.contains(u) ? Array(selection) : [u] }
    private func open(_ row: Browser.Row) { if row.isDir { selection = []; browser.load(row.url) } }
    private var biggest: Double { Double(max(1, browser.rows.compactMap(\.size).max() ?? 1)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Move to NAS", subtitle: "Pick what to move. Nothing is removed until it is verified on the NAS.") { NASChip() }
            HStack(alignment: .top, spacing: 16) {
                browserTile
                queueTile.frame(width: 340)
            }
        }
    }

    private var browserTile: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button { browser.up() } label: { Icon(glyph: .up) }.buttonStyle(IconButtonStyle())
                Button { browser.load(FileManager.default.homeDirectoryForCurrentUser) } label: { Icon(glyph: .home) }.buttonStyle(IconButtonStyle())
                Text(browser.dir.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(Typo.mono(12)).foregroundStyle(Theme.muted)
                    .lineLimit(1).truncationMode(.head)
                Spacer()
                if browser.loading { ProgressView().controlSize(.small) }
                Segmented(options: [false, true], label: { $0 ? "Biggest" : "A–Z" }, selection: $browser.sortBySize)
            }
            List(browser.rows, selection: $selection) { row in
                HStack(spacing: 12) {
                    let sel = selection.contains(row.url)
                    let style = row.isDir ? (Glyph.folder, Palette.color(for: row.url.lastPathComponent)) : Palette.fileStyle(row.url)
                    let ink: Color = sel ? .white : style.1
                    Icon(glyph: style.0, size: 17).foregroundStyle(ink)
                        .frame(width: 32, height: 32)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(sel ? Color.white.opacity(0.22) : style.1.opacity(0.16)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.url.lastPathComponent).lineLimit(1)
                        GeometryReader { g in
                            RoundedRectangle(cornerRadius: 1.5).fill(sel ? Color.white.opacity(0.8) : style.1.opacity(0.7))
                                .frame(width: max(2, g.size.width * Double(row.size ?? 0) / biggest), height: 3)
                        }.frame(height: 3)
                    }
                    Spacer(minLength: 8)
                    if let s = row.size { Text(formatBytes(s)).font(Typo.ui(13)).foregroundStyle(sel ? Color.white.opacity(0.9) : Theme.muted).monospacedDigit() }
                    else { ProgressView().controlSize(.small) }
                    Button { model.add(targets(row.url)) } label: { Icon(glyph: .plus) }
                        .buttonStyle(IconButtonStyle(tint: sel ? .white : Theme.mint)).help("Add to copy list")
                    Button { model.trash(targets(row.url)) } label: { Icon(glyph: .trash) }
                        .buttonStyle(IconButtonStyle(tint: sel ? .white : Theme.pink)).help("Move to Trash")
                }
                .padding(.vertical, 3)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture(count: 2).onEnded { open(row) })
                .listRowSeparator(.hidden)
                .contextMenu {
                    Button("Add to copy list") { model.add(targets(row.url)) }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([row.url]) }
                    Button("Move to Trash", role: .destructive) { model.trash(targets(row.url)) }
                }
            }
            .darkList()
            .focused($listFocused)
            .onDeleteCommand { model.trash(Array(selection)) }
            .onKeyPress(.return) {
                guard let r = browser.rows.first(where: { selection.contains($0.url) && $0.isDir }) else { return .ignored }
                open(r); return .handled
            }
            .onKeyPress(keys: [.upArrow]) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                browser.up(); return .handled
            }
            .onChange(of: browser.loadCount) { _, _ in
                let pick = browser.focusURL.flatMap { u in browser.rows.first { $0.url == u }?.url } ?? browser.rows.first?.url
                browser.focusURL = nil
                selection = pick.map { [$0] } ?? []
                listFocused = true
            }
            .spacePreview(selection: selection, items: browser.rows.map(\.url), preview: $preview)
            SelectionBar(selection: selection, clear: { selection = [] })
            Text("Click to select · Return opens · ⌘↑ goes up · Space previews · ⌘/⇧-click for several")
                .font(Typo.ui(11)).foregroundStyle(Theme.faint)
        }
        .bento()
    }

    private var queueTile: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Copy list").font(Typo.display(19, .bold))
                Spacer()
                if !model.queue.isEmpty { Button("Clear") { model.queue = [] }.buttonStyle(GhostButtonStyle()).disabled(model.copying) }
            }
            Text("\(model.queue.count) items · \(formatBytes(model.totalQueued))").foregroundStyle(Theme.muted)

            if model.queue.isEmpty {
                VStack(spacing: 8) {
                    Icon(glyph: .tray, size: 34).foregroundStyle(Theme.faint)
                    Text("Add files with +, or drag them here").font(Typo.ui(13)).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .background(RoundedRectangle(cornerRadius: 16).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6])).foregroundStyle(Theme.faint))
            } else {
                HStack {
                    Toggle("", isOn: Binding(get: { model.deleteAll }, set: { model.deleteAll = $0 }))
                        .toggleStyle(RoundCheckStyle(tint: Theme.pink, icon: .trash)).labelsHidden()
                    Text("Copy list to delete from MacBook").font(Typo.ui(13, .medium))
                }.disabled(model.copying)
                if !model.toDelete.isEmpty {
                    Segmented(options: DeleteMode.allCases, label: { $0.rawValue }, selection: $model.deleteMode).disabled(model.copying)
                }
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(model.queue) { item in
                            HStack(spacing: 10) {
                                Toggle("", isOn: Binding(
                                    get: { item.deleteAfter },
                                    set: { v in if let i = model.queue.firstIndex(where: { $0.id == item.id }) { model.queue[i].deleteAfter = v } }))
                                    .toggleStyle(RoundCheckStyle(tint: Theme.pink, icon: .trash)).labelsHidden()
                                    .help("Delete this from the MacBook after it is copied")
                                Text(item.url.lastPathComponent).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(item.size.map(formatBytes) ?? "…").font(Typo.ui(13)).foregroundStyle(Theme.muted).monospacedDigit()
                                Button { model.queue.removeAll { $0.id == item.id } } label: { Icon(glyph: .close) }
                                    .buttonStyle(IconButtonStyle())
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface2))
                        }
                    }
                }.frame(maxHeight: .infinity).disabled(model.copying)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 6) {
                Text("NAS FOLDER").font(Typo.ui(10, .bold)).foregroundStyle(Theme.faint)
                TextField("MacBook Archive", text: $model.folderName)
                    .textFieldStyle(.plain).padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface2))
            }
            Button { model.startCopy() } label: {
                HStack(spacing: 8) { Icon(glyph: .upload, size: 16); Text("Copy to NAS") }.frame(maxWidth: .infinity)
            }
            .buttonStyle(GlowButtonStyle(gradient: Theme.fresh, glow: Theme.mint, dark: true))
            .disabled(model.queue.isEmpty || !model.connected || model.copying)
            if model.copying || model.progress > 0 {
                RoundedRectangle(cornerRadius: 3).fill(Theme.surface2).frame(height: 6)
                    .overlay(alignment: .leading) {
                        GeometryReader { g in
                            RoundedRectangle(cornerRadius: 3).fill(Theme.mint).frame(width: g.size.width * model.progress)
                        }
                    }
            }
            if !model.message.isEmpty {
                Text(model.message).font(Typo.ui(13)).foregroundStyle(model.messageIsError ? Theme.pink : Theme.muted)
            }
        }
        .bento()
    }
}

// MARK: Tools

struct ToolsBar: View {
    /// The bundled Mole helpers are Apple-silicon builds, and one needs macOS 26.
    static var moleOK: Bool {
        #if arch(arm64)
        return ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0))
        #else
        return false
        #endif
    }
    static func runInTerminal(_ script: String) {
        let s = script.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        NSAppleScript(source: "tell application \"Terminal\"\nactivate\ndo script \"\(s)\"\nend tell")?.executeAndReturnError(nil)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Deep clean caches, logs and leftovers").font(Typo.ui(13, .semibold))
                Text("Powered by Mole (tw93/Mole, MIT) · Duplicates by fclones (pkolaczk/fclones, MIT)")
                    .font(Typo.ui(11)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button("Licenses") { if let d = Bundle.main.resourceURL?.appendingPathComponent("licenses") { NSWorkspace.shared.open(d) } }
                .buttonStyle(GhostButtonStyle())
            Button(Self.moleOK ? "Open Mole" : "Mole needs macOS 26") { if let mo = toolPath("mole/bin/mo") { Self.runInTerminal("'\(mo)'") } }
                .buttonStyle(GhostButtonStyle()).disabled(!Self.moleOK)
        }
        .bento(14)
    }
}
