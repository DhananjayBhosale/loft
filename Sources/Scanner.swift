import SwiftUI

struct SizedItem: Identifiable, Codable {
    let url: URL
    let size: Int64
    var id: URL { url }
}

/// Scans the home folder for the biggest files and folders.
@MainActor
final class StorageScanner: ObservableObject {
    @Published var files: [SizedItem] = []
    @Published var folders: [SizedItem] = []
    @Published var scanning = false
    @Published var scanned = 0
    @Published var hasResult = false
    @Published var partial = false   // true while a scan is running and the lists show what has been found so far
    private var hasComplete = false
    @Published var lastScan: Date?
    @Published var topLevel: [SizedItem] = []
    @Published var categorySizes: [String: Int64] = Persist.load([String: Int64].self, "category-sizes") ?? [:]

    private struct Snapshot: Codable { let date: Date; let files: [SizedItem]; let folders: [SizedItem]; let scanned: Int; let complete: Bool? }

    init() {
        if let s = Persist.load(Snapshot.self, "storage-scan"), !s.files.isEmpty || !s.folders.isEmpty {
            topLevel = Persist.load([SizedItem].self, "top-level") ?? []
            files = s.files; folders = s.folders; scanned = s.scanned; lastScan = s.date; hasResult = true
            partial = s.complete == false; hasComplete = s.complete != false
        }
    }

    func remove(_ gone: Set<URL>) {
        // Keep folder totals honest: take each removed item's known size off every folder that contained it.
        let known = files + folders + topLevel
        for g in gone {
            guard let freed = known.first(where: { $0.url == g })?.size else { continue }
            let shrink: (SizedItem) -> SizedItem = { i in
                g.path.hasPrefix(i.url.path + "/") ? SizedItem(url: i.url, size: max(0, i.size - freed)) : i
            }
            folders = folders.map(shrink); topLevel = topLevel.map(shrink)
        }
        Persist.save(topLevel, "top-level")
        let hit: (SizedItem) -> Bool = { i in gone.contains { i.url == $0 || i.url.path.hasPrefix($0.path + "/") } }
        files.removeAll(where: hit); folders.removeAll(where: hit)
        Persist.save(Snapshot(date: lastScan ?? Date(), files: files, folders: folders, scanned: scanned, complete: !partial), "storage-scan")
    }

    /// Sizes of well-known clearable locations, measured in parallel with `du`.
    func refreshCategories() {
        Task.detached(priority: .utility) { [weak self] in
            var out: [String: Int64] = [:]
            await withTaskGroup(of: (String, Int64).self) { g in
                for c in SpaceCategory.all { for p in c.paths { g.addTask { (c.id, await Browser.duSize(p) ?? 0) } } }
                for await (id, s) in g { out[id, default: 0] += s }
            }
            let result = out
            await MainActor.run { self?.categorySizes = result; Persist.save(result, "category-sizes") }
        }
    }

    /// Biggest 100 files, biggest 100 folders (up to 3 levels deep) and the home folder's direct children.
    nonisolated static func summarize(_ top: [SizedItem], _ dirs: [String: Int64], _ rootPath: String) -> ([SizedItem], [SizedItem], [SizedItem]) {
        let f = Array(top.sorted { $0.size > $1.size }.prefix(100))
        let sorted = dirs.sorted { $0.value > $1.value }
        let d = sorted.prefix(100).map { SizedItem(url: URL(fileURLWithPath: $0.key), size: $0.value) }
        let tl = sorted.filter { !$0.key.dropFirst(rootPath.count + 1).contains("/") }
            .map { SizedItem(url: URL(fileURLWithPath: $0.key), size: $0.value) }
        return (f, d, tl)
    }

    /// Live results while a scan runs. A partial snapshot is saved only when no finished scan exists yet,
    /// so a quit mid-scan never replaces a complete earlier result.
    private func showPartial(_ f: [SizedItem], _ d: [SizedItem], _ tl: [SizedItem], _ count: Int, save: Bool) {
        guard scanning else { return }
        files = f; folders = d; topLevel = tl; scanned = count
        if save && !hasComplete {
            Persist.save(Snapshot(date: Date(), files: f, folders: d, scanned: count, complete: false), "storage-scan")
            Persist.save(tl, "top-level")
        }
    }

    func scan() {
        guard !scanning else { return }
        scanning = true; scanned = 0; partial = true; hasResult = true
        let root = FileManager.default.homeDirectoryForCurrentUser
        Task.detached(priority: .utility) { [weak self] in
            var top: [SizedItem] = []
            var minTop: Int64 = 0
            var dirs: [String: Int64] = [:]
            var count = 0
            var lastPublish = Date()
            var lastSave = Date()
            let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey]
            let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true })
            let rootPath = root.path
            while let u = e?.nextObject() as? URL {
                guard let v = try? u.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
                let s = Int64(v.totalFileAllocatedSize ?? 0)
                count += 1
                if s > minTop || top.count < 100 {
                    top.append(SizedItem(url: u, size: s))
                    if top.count > 200 { top.sort { $0.size > $1.size }; top = Array(top.prefix(100)); minTop = top.last?.size ?? 0 }
                }
                let parts = u.path.dropFirst(rootPath.count + 1).split(separator: "/").dropLast()
                var path = rootPath
                for p in parts.prefix(3) { path += "/" + p; dirs[path, default: 0] += s }
                if count % 500 == 0, Date().timeIntervalSince(lastPublish) > 0.7 {
                    lastPublish = Date()
                    let (f, d, tl) = Self.summarize(top, dirs, rootPath)
                    let c = count
                    let save = Date().timeIntervalSince(lastSave) > 20
                    if save { lastSave = Date() }
                    await MainActor.run { self?.showPartial(f, d, tl, c, save: save) }
                }
            }
            let (f, d, tl) = Self.summarize(top, dirs, rootPath)
            await MainActor.run {
                self?.files = f; self?.folders = d; self?.topLevel = tl; self?.scanned = count
                self?.scanning = false; self?.partial = false; self?.hasComplete = true; self?.hasResult = true; self?.lastScan = Date()
                Persist.save(tl, "top-level")
                self?.refreshCategories()
                Persist.save(Snapshot(date: Date(), files: f, folders: d, scanned: count, complete: true), "storage-scan")
            }
        }
    }
}
