import SwiftUI
import AppKit
import CryptoKit

/// NAS address. Change with: defaults write com.dhananjay.loft nasHost <ip-or-hostname>
var nasIP: String { UserDefaults.standard.string(forKey: "nasHost") ?? "192.168.50.220" }

func formatBytes(_ b: Int64) -> String {
    let f = ByteCountFormatter(); f.countStyle = .file; f.allowsNonnumericFormatting = false
    return f.string(fromByteCount: b)
}

enum Persist {
    static var dir: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Loft")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static func save<T: Encodable>(_ v: T, _ name: String) { try? JSONEncoder().encode(v).write(to: dir.appendingPathComponent(name + ".json"), options: .atomic) }
    static func load<T: Decodable>(_ t: T.Type, _ name: String) -> T? {
        guard let d = try? Data(contentsOf: dir.appendingPathComponent(name + ".json")) else { return nil }
        return try? JSONDecoder().decode(t, from: d)
    }
}

func ago(_ d: Date) -> String {
    RelativeDateTimeFormatter().localizedString(for: d, relativeTo: Date())
}

/// True when the item lives inside the home folder (and is not the home folder itself).
func isInsideHome(_ u: URL) -> Bool {
    let home = NSHomeDirectory()
    let parent = u.deletingLastPathComponent().resolvingSymlinksInPath().path
    return parent == home || parent.hasPrefix(home + "/")
}

struct Share: Hashable { let name: String; let mount: String }

struct QueueItem: Identifiable {
    let id = UUID()
    let url: URL
    var size: Int64?
    var deleteAfter = false
}

/// Total on-disk size of a file or folder.
func diskSize(of url: URL) -> Int64 {
    let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
    var total: Int64 = 0
    if let v = try? url.resourceValues(forKeys: keys), v.isRegularFile == true {
        return Int64(v.totalFileAllocatedSize ?? 0)
    }
    if let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) {
        for case let u as URL in e {
            if let v = try? u.resourceValues(forKeys: keys), v.isRegularFile == true {
                total += Int64(v.totalFileAllocatedSize ?? 0)
            }
        }
    }
    return total
}

enum Appearance: String, CaseIterable {
    case system, light, dark
    var scheme: ColorScheme? { self == .light ? .light : self == .dark ? .dark : nil }
    var glyph: Glyph { self == .light ? .sun : self == .dark ? .moon : .auto }
    var label: String { rawValue.capitalized }
    var next: Appearance { Appearance.allCases[(Appearance.allCases.firstIndex(of: self)! + 1) % Appearance.allCases.count] }
}

enum DeleteMode: String, CaseIterable { case trash = "Move to Trash", permanent = "Fully Delete" }

@MainActor
final class AppModel: ObservableObject {
    enum Tab: String, CaseIterable { case storage = "Overview", copy = "Move to NAS", duplicates = "Duplicates", biggest = "Biggest" }

    @Published var tab: Tab = .storage
    @Published var appearance = Appearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance") }
    }
    let browser = Browser()
    let scanner = StorageScanner()
    let finder = DuplicateFinder()
    @Published var shares: [Share] = []
    @Published var selectedShare = ""
    @Published var queue: [QueueItem] = []
    @Published var deleteMode = DeleteMode(rawValue: UserDefaults.standard.string(forKey: "deleteMode") ?? "") ?? .trash {
        didSet { UserDefaults.standard.set(deleteMode.rawValue, forKey: "deleteMode") }
    }
    @Published var folderName = "MacBook Archive"
    @Published var copying = false
    @Published var progress = 0.0
    @Published var message = ""
    @Published var messageIsError = false

    private var timer: Timer?

    init() {
        if let t = UserDefaults.standard.string(forKey: "startTab"), let tab = Tab.allCases.first(where: { String(describing: $0) == t }) { self.tab = tab }
        refreshShares()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshShares() }
        }
    }

    var connected: Bool { !shares.isEmpty }

    func refreshShares() {
        var buf: UnsafeMutablePointer<statfs>?
        let n = getmntinfo(&buf, MNT_NOWAIT)
        var found: [Share] = []
        for i in 0..<Int(n) {
            guard let fs = buf?[i] else { continue }
            let from = withUnsafeBytes(of: fs.f_mntfromname) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
            let on = withUnsafeBytes(of: fs.f_mntonname) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
            if from.hasPrefix("//"), from.contains(nasIP) {
                found.append(Share(name: ((from as NSString).lastPathComponent).removingPercentEncoding ?? (from as NSString).lastPathComponent, mount: on))
            }
        }
        if found != shares { shares = found }
        if !found.contains(where: { $0.name == selectedShare }) { selectedShare = found.first?.name ?? "" }
    }

    func connect() {
        NSWorkspace.shared.open(URL(string: "smb://\(nasIP)")!)
    }

    func add(_ urls: [URL]) {
        for u in urls where !shares.contains(where: { u.path.hasPrefix($0.mount + "/") || u.path == $0.mount })
            && !queue.contains(where: { $0.url == u || u.path.hasPrefix($0.url.path + "/") }) {
            queue.removeAll { $0.url.path.hasPrefix(u.path + "/") }
            let item = QueueItem(url: u)
            queue.append(item)
            let id = item.id
            Task.detached {
                let s = diskSize(of: u)
                await MainActor.run { [weak self] in
                    if let i = self?.queue.firstIndex(where: { $0.id == id }) { self?.queue[i].size = s }
                }
            }
        }
    }

    /// Moves items to the Trash after confirming. Only items inside the home folder are allowed.
    func trash(_ urls: [URL], detail: String? = nil) {
        let allowed = urls.filter(isInsideHome)
        guard !allowed.isEmpty else {
            if !urls.isEmpty {
                let n = NSAlert(); n.messageText = "Only items in your home folder can be deleted here."; n.runModal()
            }
            return
        }
        let a = NSAlert()
        a.messageText = allowed.count == 1 ? "Move “\(allowed[0].lastPathComponent)” to the Trash?" : "Move \(allowed.count) items to the Trash?"
        a.informativeText = (detail.map { $0 + "\n\n" } ?? "") + "You can restore them from the Trash. Space is freed when you empty it."
            + (allowed.count < urls.count ? "\n\(urls.count - allowed.count) item(s) outside your home folder were skipped." : "")
        a.addButton(withTitle: "Cancel"); a.addButton(withTitle: "Move to Trash")
        a.alertStyle = .warning
        guard a.runModal() == .alertSecondButtonReturn else { return }
        var gone = Set<URL>(); var failed: [String] = []
        for u in allowed {
            do { try FileManager.default.trashItem(at: u, resultingItemURL: nil); gone.insert(u) }
            catch { failed.append(u.lastPathComponent) }
        }
        browser.remove(gone); scanner.remove(gone); finder.remove(gone)
        queue.removeAll { gone.contains($0.url) }
        if !failed.isEmpty {
            let f = NSAlert()
            f.messageText = "Couldn’t move \(failed.count) item(s) to the Trash"
            f.informativeText = failed.prefix(5).joined(separator: ", ")
            f.runModal()
        }
    }

    func choose() {
        let p = NSOpenPanel()
        p.canChooseFiles = true; p.canChooseDirectories = true; p.allowsMultipleSelection = true
        p.prompt = "Add"
        if p.runModal() == .OK { add(p.urls) }
    }

    var deleteAll: Bool {
        get { !queue.isEmpty && queue.allSatisfy(\.deleteAfter) }
        set { for i in queue.indices { queue[i].deleteAfter = newValue } }
    }
    var toDelete: [QueueItem] { queue.filter(\.deleteAfter) }

    var totalQueued: Int64 { queue.reduce(0) { $0 + ($1.size ?? 0) } }

    func startCopy() {
        guard let share = shares.first(where: { $0.name == selectedShare }), !queue.isEmpty else { return }
        let doomed = toDelete
        if !doomed.isEmpty {
            let a = NSAlert()
            let size = formatBytes(doomed.reduce(0) { $0 + ($1.size ?? 0) })
            a.messageText = deleteMode == .trash
                ? "Move \(doomed.count) original item(s) to the Trash after copying?"
                : "Permanently delete \(doomed.count) original item(s) after copying?"
            a.informativeText = (deleteMode == .trash
                ? "\(size) will be moved to the Trash once every file is copied and its contents are checked on the NAS. Empty the Trash to free the space."
                : "\(size) will be permanently deleted from this Mac, with no way to undo, once every file is copied and its contents are checked on the NAS.")
                + "\n\nThe NAS keeps file contents and dates, but not Finder tags or other extended attributes."
            a.addButton(withTitle: "Cancel"); a.addButton(withTitle: "Copy and Delete")
            a.alertStyle = .warning
            if a.runModal() != .alertSecondButtonReturn { return }
        }
        var folder = folderName.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        if folder.isEmpty || folder == "." || folder == ".." { folder = "MacBook Archive" }
        let dest = URL(fileURLWithPath: share.mount).appendingPathComponent(folder)
        let ids = Set(queue.map(\.id))
        let items = queue.map(\.url), del = doomed.map(\.url), mode = deleteMode
        copying = true; progress = 0; message = "Starting…"; messageIsError = false
        Task.detached {
            do {
                let total = try Copier.copy(items, to: dest, verifyContent: !del.isEmpty) { done, total, label in
                    Task { @MainActor [weak self] in
                        self?.progress = total > 0 ? Double(done) / Double(total) : 0
                        self?.message = "\(label) — \(formatBytes(done)) of \(formatBytes(total))"
                    }
                }
                var deleted: [URL] = [], notDeleted: [String] = []
                for u in del where FileManager.default.fileExists(atPath: u.path) {
                    guard isInsideHome(u) else { notDeleted.append(u.lastPathComponent); continue }
                    do {
                        if mode == .trash { try FileManager.default.trashItem(at: u, resultingItemURL: nil) }
                        else { try FileManager.default.removeItem(at: u) }
                        deleted.append(u)
                    } catch { notDeleted.append(u.lastPathComponent) }
                }
                let gone = Set(deleted), left = notDeleted
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.copying = false; self.progress = 1
                    self.queue.removeAll { ids.contains($0.id) }
                    self.browser.remove(gone); self.scanner.remove(gone); self.finder.remove(gone)
                    var msg = "Done — \(formatBytes(total)) copied to “\(dest.lastPathComponent)” on the NAS."
                    if !gone.isEmpty { msg += mode == .trash ? " \(gone.count) original(s) moved to the Trash." : " \(gone.count) original(s) deleted from this Mac." }
                    if !left.isEmpty { msg += " Copied, but could not remove: \(left.prefix(3).joined(separator: ", "))."; self.messageIsError = true }
                    self.message = msg
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.copying = false; self?.messageIsError = true
                    self?.message = "Failed: \(error.localizedDescription) Nothing was deleted from your Mac."
                }
            }
        }
    }
}

enum Copier {
    struct Failure: LocalizedError { let errorDescription: String? }
    private final class Created { var urls: [URL] = [] }

    /// Next free name, also avoiding names already handed out in this batch.
    static func unique(_ url: URL, reserved: inout Set<String>) -> URL {
        let fm = FileManager.default
        func taken(_ u: URL) -> Bool { fm.fileExists(atPath: u.path) || reserved.contains(u.path) }
        var cand = url
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        var i = 2
        while taken(cand) {
            cand = url.deletingLastPathComponent().appendingPathComponent(ext.isEmpty ? "\(base) (\(i))" : "\(base) (\(i)).\(ext)")
            i += 1
        }
        reserved.insert(cand.path)
        return cand
    }

    /// Copies items into `dest`. Every file is size-checked; with `verifyContent` the copy is also read back and
    /// compared by SHA-256, and the source must be unchanged. On any failure, what this run created is removed.
    static func copy(_ items: [URL], to dest: URL, verifyContent: Bool = true,
                     progress: @escaping @Sendable (Int64, Int64, String) -> Void) throws -> Int64 {
        let created = Created()
        do { return try run(items, to: dest, verify: verifyContent, created: created, progress: progress) }
        catch {
            for u in created.urls { try? FileManager.default.removeItem(at: u) }
            throw error
        }
    }

    private struct Job { let src: URL; let dst: URL; let size: Int64; let mtime: Date? }

    private static func run(_ items: [URL], to dest: URL, verify: Bool, created: Created,
                            progress: @escaping @Sendable (Int64, Int64, String) -> Void) throws -> Int64 {
        let fm = FileManager.default
        let existed = fm.fileExists(atPath: dest.path)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        if !existed { created.urls.append(dest) }
        var reserved = Set<String>()
        var jobs: [Job] = []
        func job(_ s: URL, _ d: URL) throws {
            let at = try fm.attributesOfItem(atPath: s.path)
            jobs.append(Job(src: s, dst: d, size: (at[.size] as? NSNumber)?.int64Value ?? 0, mtime: at[.modificationDate] as? Date))
        }
        for item in items {
            let target = unique(dest.appendingPathComponent(item.lastPathComponent), reserved: &reserved)
            if existed { created.urls.append(target) }
            let v = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if v?.isSymbolicLink == true {
                try fm.createSymbolicLink(atPath: target.path, withDestinationPath: try fm.destinationOfSymbolicLink(atPath: item.path))
            } else if v?.isDirectory == true {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                var walkErrors: [String] = []
                if let e = fm.enumerator(at: item, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
                                         errorHandler: { url, _ in walkErrors.append(url.lastPathComponent); return true }) {
                    for case let u as URL in e {
                        let out = target.appendingPathComponent(String(u.path.dropFirst(item.path.count + 1)))
                        let r = try? u.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
                        if r?.isSymbolicLink == true {
                            try fm.createSymbolicLink(atPath: out.path, withDestinationPath: try fm.destinationOfSymbolicLink(atPath: u.path))
                        } else if r?.isDirectory == true { try fm.createDirectory(at: out, withIntermediateDirectories: true) }
                        else if r?.isRegularFile == true { try job(u, out) }
                        else { walkErrors.append(u.lastPathComponent + " (unsupported file type)") }
                    }
                } else { walkErrors.append(item.lastPathComponent) }
                if !walkErrors.isEmpty {
                    throw Failure(errorDescription: "Couldn’t read \(walkErrors.count) item(s) in “\(item.lastPathComponent)” (e.g. \(walkErrors[0])).")
                }
            } else if v?.isDirectory == false {
                try job(item, target)
            } else { throw Failure(errorDescription: "Couldn’t read “\(item.lastPathComponent)”.") }
        }
        let total = jobs.reduce(Int64(0)) { $0 + $1.size }
        var done: Int64 = 0
        for j in jobs {
            guard fm.createFile(atPath: j.dst.path, contents: nil) else { throw Failure(errorDescription: "Couldn’t create “\(j.dst.lastPathComponent)” on the destination.") }
            var hasher = SHA256()
            do {
                let r = try FileHandle(forReadingFrom: j.src), w = try FileHandle(forWritingTo: j.dst)
                defer { try? r.close(); try? w.close() }
                while let chunk = try r.read(upToCount: 4 << 20), !chunk.isEmpty {
                    try w.write(contentsOf: chunk)
                    if verify { hasher.update(data: chunk) }
                    done += Int64(chunk.count)
                    progress(done, total, "Copying \(j.src.lastPathComponent)")
                }
                try w.synchronize()
            }
            if let m = j.mtime { try? fm.setAttributes([.modificationDate: m], ofItemAtPath: j.dst.path) }
            if let perm = (try? fm.attributesOfItem(atPath: j.src.path)[.posixPermissions]) { try? fm.setAttributes([.posixPermissions: perm], ofItemAtPath: j.dst.path) }
            let after = try fm.attributesOfItem(atPath: j.src.path)
            let copied = ((try fm.attributesOfItem(atPath: j.dst.path))[.size] as? NSNumber)?.int64Value ?? -1
            if (after[.size] as? NSNumber)?.int64Value != j.size || (after[.modificationDate] as? Date) != j.mtime {
                throw Failure(errorDescription: "“\(j.src.lastPathComponent)” changed while it was being copied.")
            }
            if copied != j.size { throw Failure(errorDescription: "Size mismatch after copying “\(j.src.lastPathComponent)”.") }
            if verify {
                progress(done, total, "Verifying \(j.src.lastPathComponent)")
                var check = SHA256()
                let rb = try FileHandle(forReadingFrom: j.dst)
                defer { try? rb.close() }
                while let chunk = try rb.read(upToCount: 4 << 20), !chunk.isEmpty { check.update(data: chunk) }
                if Data(check.finalize()) != Data(hasher.finalize()) {
                    throw Failure(errorDescription: "Contents of “\(j.src.lastPathComponent)” did not match after copying.")
                }
            }
        }
        return total
    }
}
