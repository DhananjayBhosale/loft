import SwiftUI
import AppKit

/// Path to a bundled helper tool (falls back to Homebrew for development builds).
func toolPath(_ relative: String) -> String? {
    var candidates: [String] = []
    if let r = Bundle.main.resourcePath { candidates.append(r + "/tools/" + relative) }
    candidates.append("/opt/homebrew/bin/" + (relative as NSString).lastPathComponent)
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
}

struct DupGroup: Identifiable, Codable {
    var id = UUID()
    let size: Int64
    var files: [URL]
    enum CodingKeys: String, CodingKey { case size, files }
    init(size: Int64, files: [URL]) { self.size = size; self.files = files }
    var wasted: Int64 { size * Int64(files.count - 1) }
}

/// Finds duplicate files with fclones (github.com/pkolaczk/fclones, MIT).
@MainActor
final class DuplicateFinder: ObservableObject {
    @Published var groups: [DupGroup] = []
    @Published var selected = Set<URL>()
    @Published var running = false
    @Published var hasResult = false
    @Published var error = ""
    @Published var minSizeMB = 10
    @Published var lastScan: Date?

    private struct Snapshot: Codable { let date: Date; let groups: [DupGroup]; let minSizeMB: Int }

    init() {
        if let s = Persist.load(Snapshot.self, "duplicates") {
            groups = s.groups.map { var g = $0; g.files = g.files.filter { FileManager.default.fileExists(atPath: $0.path) }; return g }
                .filter { $0.files.count > 1 }
            minSizeMB = s.minSizeMB; lastScan = s.date; hasResult = true
        }
    }

    private func save() { Persist.save(Snapshot(date: lastScan ?? Date(), groups: groups, minSizeMB: minSizeMB), "duplicates") }

    var totalWasted: Int64 { groups.reduce(0) { $0 + $1.wasted } }
    var selectedBytes: Int64 { groups.reduce(0) { acc, g in acc + g.size * Int64(g.files.filter(selected.contains).count) } }

    func scan() {
        guard !running, let tool = toolPath("fclones") else { error = "fclones is missing from the app."; return }
        running = true; error = ""; selected = []
        let minBytes = minSizeMB * 1_000_000
        let home = NSHomeDirectory()
        Task.detached(priority: .utility) { [weak self] in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = ["group", home, "--min", String(minBytes), "--format", "json", "--exclude", home + "/Library/**", "--exclude", "**/.git/**", "--exclude", "**/node_modules/**", "--exclude", "**/*.app/**"]
            let out = Pipe()
            p.standardOutput = out; p.standardError = FileHandle.nullDevice
            var result: [DupGroup] = []
            var err = ""
            do {
                try p.run()
                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let gs = json["groups"] as? [[String: Any]] {
                    for g in gs {
                        let size = (g["file_len"] as? NSNumber)?.int64Value ?? 0
                        let files = (g["files"] as? [String] ?? []).map { URL(fileURLWithPath: $0) }
                        if files.count > 1 { result.append(DupGroup(size: size, files: files)) }
                    }
                }
            } catch { err = error.localizedDescription }
            result.sort { $0.wasted > $1.wasted }
            await MainActor.run {
                guard let self else { return }
                self.groups = result; self.error = err; self.running = false; self.hasResult = true; self.lastScan = Date(); self.save()
            }
        }
    }

    /// Select every copy except the first in each group.
    func autoSelect() {
        selected = Set(groups.flatMap { $0.files.dropFirst() })
    }

    /// A group must always keep at least one unselected copy.
    func toggle(_ url: URL, in group: DupGroup) {
        if selected.contains(url) { selected.remove(url); return }
        if group.files.filter({ !selected.contains($0) }).count > 1 { selected.insert(url) }
    }

    func remove(_ gone: Set<URL>) {
        for i in groups.indices { groups[i].files.removeAll { gone.contains($0) } }
        groups.removeAll { $0.files.count < 2 }
        selected.formIntersection(Set(groups.flatMap(\.files)))
        save()
    }

    func trashSelected() {
        // Re-check everything just before deleting: files must still exist with the same size, and each
        // group must keep at least one live, unselected copy.
        let fm = FileManager.default
        var plan: [URL] = []
        for g in groups {
            let live = g.files.filter { u in
                let sz = (try? fm.attributesOfItem(atPath: u.path)[.size] as? NSNumber)?.int64Value
                return sz == g.size
            }
            let victims = live.filter { selected.contains($0) && isInsideHome($0) }
            if victims.count < live.count { plan += victims }   // else: nothing would be left, so keep them all
        }
        guard !plan.isEmpty else { error = "Nothing to move: each group must keep at least one copy."; return }
        let a = NSAlert()
        a.messageText = "Move \(plan.count) duplicate file(s) to the Trash?"
        a.informativeText = "\(formatBytes(plan.reduce(0) { acc, u in acc + ((try? fm.attributesOfItem(atPath: u.path)[.size] as? NSNumber)?.int64Value ?? 0) })) will move to the Trash. One copy in each group is always kept."
        a.addButton(withTitle: "Cancel"); a.addButton(withTitle: "Move to Trash")
        a.alertStyle = .warning
        guard a.runModal() == .alertSecondButtonReturn else { return }
        var gone = Set<URL>(); var failed: [String] = []
        for u in plan { do { try fm.trashItem(at: u, resultingItemURL: nil); gone.insert(u) } catch { failed.append(u.lastPathComponent) } }
        remove(gone)
        error = failed.isEmpty ? "" : "Could not move to the Trash: \(failed.prefix(3).joined(separator: ", "))."
    }
}

struct DuplicatesView: View {
    @ObservedObject var finder: DuplicateFinder
    @State private var selection = Set<URL>()
    @State private var preview: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Duplicates", subtitle: finder.hasResult
                       ? "\(finder.groups.count) groups · scanned \(ago(finder.lastScan ?? Date()))"
                       : "Identical files, matched byte for byte.") {
                HStack(spacing: 10) {
                    if finder.running { ProgressView().controlSize(.small) }
                    Segmented(options: [1, 10, 100], label: { "\($0) MB+" }, selection: $finder.minSizeMB).disabled(finder.running)
                    Button(finder.hasResult ? "Rescan" : "Find duplicates") { finder.scan() }
                        .buttonStyle(GlowButtonStyle()).disabled(finder.running)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(formatBytes(finder.totalWasted)).font(Typo.display(54, .heavy)).monospacedDigit()
                    .foregroundStyle(Theme.warm)
                Text("wasted on extra copies").foregroundStyle(Theme.muted)
            }
            .bento(20)
            if !finder.error.isEmpty { Text(finder.error).foregroundStyle(Theme.pink) }
            if finder.hasResult && finder.groups.isEmpty {
                Text("No duplicates found.").foregroundStyle(Theme.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if finder.hasResult {
                List(selection: $selection) {
                    ForEach(finder.groups) { g in
                        Section {
                            ForEach(g.files, id: \.self) { f in
                                HStack(spacing: 12) {
                                    Toggle("", isOn: Binding(get: { finder.selected.contains(f) }, set: { _ in finder.toggle(f, in: g) }))
                                        .toggleStyle(RoundCheckStyle(tint: Theme.pink, icon: .trash)).labelsHidden()
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(f.lastPathComponent).lineLimit(1)
                                        Text(f.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                            .font(Typo.ui(11)).foregroundStyle(Theme.faint).lineLimit(1).truncationMode(.head)
                                    }
                                    Spacer()
                                    Chip(text: finder.selected.contains(f) ? "Trash" : "Keep", color: finder.selected.contains(f) ? Theme.pink : Theme.mint)
                                    Button { NSWorkspace.shared.activateFileViewerSelecting([f]) } label: { Icon(glyph: .search) }
                                        .buttonStyle(IconButtonStyle()).help("Show in Finder")
                                }
                                .listRowSeparator(.hidden)
                            }
                        } header: {
                            HStack(spacing: 8) {
                                Chip(text: "\(g.files.count) copies", color: Theme.amber)
                                Text("\(formatBytes(g.size)) each · \(formatBytes(g.wasted)) wasted").font(Typo.ui(13)).foregroundStyle(Theme.muted)
                            }.padding(.top, 8)
                        }
                    }
                }
                .darkList()
                .spacePreview(selection: selection, items: finder.groups.flatMap(\.files), preview: $preview)
                .bento(8)
                HStack {
                    Button("Select extra copies") { finder.autoSelect() }.buttonStyle(GhostButtonStyle())
                    Text("Keeps the first copy in each group.").font(Typo.ui(11)).foregroundStyle(Theme.faint)
                    Spacer()
                    Text("\(finder.selected.count) selected · \(formatBytes(finder.selectedBytes))").foregroundStyle(Theme.muted)
                    Button("Move to Trash") { finder.trashSelected() }
                        .buttonStyle(GlowButtonStyle(gradient: Theme.warm, glow: Theme.pink)).disabled(finder.selected.isEmpty)
                }
                .padding(12).background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
            } else if !finder.running {
                Spacer()
            }
        }
    }
}
