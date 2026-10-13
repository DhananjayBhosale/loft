import SwiftUI

/// Folder browser. Listing happens off the main thread and shows instantly;
/// folder sizes are filled in afterwards by cancellable background `du` runs.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false, _started = false
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return _cancelled }
    var started: Bool { get { lock.lock(); defer { lock.unlock() }; return _started } set { lock.lock(); _started = newValue; lock.unlock() } }
    func cancel() { lock.lock(); _cancelled = true; lock.unlock() }
}

@MainActor
final class Browser: ObservableObject {
    struct Row: Identifiable {
        let url: URL
        let isDir: Bool
        var size: Int64?
        var id: URL { url }
    }

    @Published var dir = FileManager.default.homeDirectoryForCurrentUser
    @Published var rows: [Row] = []
    @Published var loading = false
    @Published var loadCount = 0
    var focusURL: URL?
    @Published var sortBySize = false { didSet { sortRows() } }

    private struct Entry: Codable { let size: Int64; let date: Date }
    private var cache: [String: Entry] = Persist.load([String: Entry].self, "folder-sizes") ?? [:]
    private let maxAge: TimeInterval = 6 * 3600
    private var loadTask: Task<Void, Never>?
    private var sizeTask: Task<Void, Never>?

    init() { load(dir) }

    func load(_ url: URL) {
        dir = url
        loadTask?.cancel(); sizeTask?.cancel()
        loading = true
        loadTask = Task { [weak self] in
            let listing = await Task.detached(priority: .userInitiated) { Browser.list(url) }.value
            guard !Task.isCancelled, let self else { return }
            self.rows = listing.map { Row(url: $0.0, isDir: $0.1, size: $0.1 ? self.cache[$0.0.path]?.size : $0.2) }
            self.sortRows()
            self.loading = false
            self.loadCount += 1
            self.startSizing()
        }
    }

    nonisolated private static func list(_ url: URL) -> [(URL, Bool, Int64)] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .totalFileAllocatedSizeKey]
        let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return items.map { u in
            let v = try? u.resourceValues(forKeys: Set(keys))
            return (u, v?.isDirectory ?? false, Int64(v?.totalFileAllocatedSize ?? 0))
        }
    }

    private func startSizing() {
        let pending = rows.filter { r in
            r.isDir && (cache[r.url.path].map { Date().timeIntervalSince($0.date) > maxAge } ?? true)
        }.map(\.url)
        guard !pending.isEmpty else { return }
        sizeTask = Task.detached(priority: .utility) { [weak self] in
            await withTaskGroup(of: (URL, Int64?).self) { group in
                var iterator = pending.makeIterator()
                for _ in 0..<4 { if let u = iterator.next() { group.addTask { (u, await Browser.duSize(u)) } } }
                var batch: [(URL, Int64)] = []
                var last = Date()
                while let (u, s) = await group.next() {
                    if Task.isCancelled { group.cancelAll(); break }
                    if let s { batch.append((u, s)) }
                    if let n = iterator.next() { group.addTask { (n, await Browser.duSize(n)) } }
                    if Date().timeIntervalSince(last) > 0.3, !batch.isEmpty {
                        let b = batch; batch = []; last = Date()
                        await MainActor.run { self?.apply(b) }
                    }
                }
                if !batch.isEmpty { let b = batch; await MainActor.run { self?.apply(b) } }
            }
            await MainActor.run { if let self { Persist.save(self.cache, "folder-sizes") } }
        }
    }

    private func apply(_ batch: [(URL, Int64)]) {
        let index = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($1.url, $0) })
        for (u, s) in batch {
            cache[u.path] = Entry(size: s, date: Date())
            if let i = index[u] { rows[i].size = s }
        }
        if sortBySize { sortRows() }
    }

    /// Size of a folder via `du`, which is much faster than walking it in Swift. Cancellable.
    nonisolated static func duSize(_ url: URL) async -> Int64? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        p.arguments = ["-skx", url.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        let flag = CancelFlag()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Int64?, Never>) in
                DispatchQueue.global(qos: .utility).async {
                    if flag.cancelled { cont.resume(returning: nil); return }
                    do { try p.run() } catch { cont.resume(returning: nil); return }
                    flag.started = true
                    if flag.cancelled { p.terminate() }
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    p.waitUntilExit()
                    guard p.terminationReason == .exit,
                          let first = String(data: data, encoding: .utf8)?.split(whereSeparator: \.isWhitespace).first,
                          let kb = Int64(first) else { cont.resume(returning: nil); return }
                    cont.resume(returning: kb * 1024)
                }
            }
        } onCancel: {
            flag.cancel()
            if flag.started, p.isRunning { p.terminate() }
        }
    }

    func remove(_ gone: Set<URL>) {
        rows.removeAll { gone.contains($0.url) }
        for u in gone { cache[u.path] = nil }
        Persist.save(cache, "folder-sizes")
    }

    func up() {
        guard dir.path != "/" else { return }
        focusURL = dir
        load(dir.deletingLastPathComponent())
    }

    private func sortRows() {
        rows.sort { a, b in
            if sortBySize { return (a.size ?? -1) > (b.size ?? -1) }
            if a.isDir != b.isDir { return a.isDir }
            return a.url.lastPathComponent.localizedStandardCompare(b.url.lastPathComponent) == .orderedAscending
        }
    }
}
