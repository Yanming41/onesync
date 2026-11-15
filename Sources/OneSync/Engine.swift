import Foundation
import SwiftUI
import Security

// MARK: - 设置（UserDefaults）

struct Settings {
    private static let d = UserDefaults.standard
    static var rclonePath: String {
        get { d.string(forKey: "rclonePath") ?? Self.detectRclone() }
        set { d.set(newValue, forKey: "rclonePath") }
    }
    /// rclone 配置文件：默认自动挑 ~/.config/rclone 下没加密、含 onedrive 的那个
    static var configPath: String {
        get { d.string(forKey: "configPath") ?? Self.detectConfig() }
        set { d.set(newValue, forKey: "configPath") }
    }
    static func isEncrypted(_ path: String) -> Bool {
        ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "").hasPrefix("# Encrypted rclone")
    }
    static func detectConfig() -> String {
        let dir = NSHomeDirectory() + "/.config/rclone"
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
            .filter { $0.hasSuffix(".conf") }.map { dir + "/" + $0 }
        func score(_ p: String) -> Int {
            let s = (try? String(contentsOfFile: p, encoding: .utf8)) ?? ""
            return (s.contains("type = onedrive") ? 2 : 0) + (isEncrypted(p) ? 0 : 1)
        }
        return files.max { score($0) < score($1) } ?? dir + "/rclone.conf"
    }

    static var remote: String {           // 例如 "onedrive"（不带冒号）
        get { d.string(forKey: "remote") ?? "" }
        set { d.set(newValue, forKey: "remote") }
    }
    static var localPath: String {
        get { d.string(forKey: "localPath") ?? NSHomeDirectory() + "/OneDrive" }  // 默认 ~/OneDrive
        set { d.set(newValue, forKey: "localPath") }
    }
    static var remotePath: String {       // OneDrive 内的目录，不能是根目录
        get { d.string(forKey: "remotePath") ?? "OneSync" }  // 默认云端 OneSync 文件夹
        set { d.set(newValue, forKey: "remotePath") }
    }
    static var lastSync: Date? {
        get { d.object(forKey: "lastSync") as? Date }
        set { d.set(newValue, forKey: "lastSync") }
    }
    /// 已建立 bisync 基线的目录对；目录改了就要重新 resync
    static var baselineKey: String {
        get { d.string(forKey: "baselineKey") ?? "" }
        set { d.set(newValue, forKey: "baselineKey") }
    }
    static var pairKey: String { "\(localPath)|\(remote):\(remotePath)" }
    static var isConfigured: Bool { !remote.isEmpty && !localPath.isEmpty && !remotePath.isEmpty }

    static func detectRclone() -> String {
        let home = NSHomeDirectory()
        for p in ["\(home)/.local/bin/rclone", "/opt/homebrew/bin/rclone", "/usr/local/bin/rclone", "\(home)/bin/rclone"]
        where FileManager.default.isExecutableFile(atPath: p) { return p }
        return "rclone"
    }
}

// MARK: - rclone 配置密码存钥匙串

enum Keychain {
    private static let service = (Bundle.main.bundleIdentifier ?? "io.github.onesync") + ".rclone-config"
    static func get() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    /// 返回是否真的写进去了（旧条目属于旧签名时删除/覆盖可能被拒）
    @discardableResult
    static func set(_ pw: String) -> Bool {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        let data = Data(pw.utf8)
        var st = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if st == errSecItemNotFound {
            var add = base; add[kSecValueData as String] = data
            st = SecItemAdd(add as CFDictionary, nil)
        } else if st != errSecSuccess {
            SecItemDelete(base as CFDictionary)
            var add = base; add[kSecValueData as String] = data
            st = SecItemAdd(add as CFDictionary, nil)
        }
        if st != errSecSuccess { NSLog("OneSync keychain write failed: \(st)") }
        return get() == pw
    }
    static func clear() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }
}

// MARK: - 跑 rclone

struct RcloneResult { var code: Int32; var output: String }

enum Rclone {
    static var overridePassword: String?   // 验证密码时临时用，不读钥匙串
    static var env: [String: String] {
        var e = ProcessInfo.processInfo.environment
        if let pw = overridePassword ?? Keychain.get() { e["RCLONE_CONFIG_PASS"] = pw }
        e["RCLONE_ASK_PASSWORD"] = "false"   // 没密码时直接报错，别卡住等输入
        return e
    }

    /// 运行 rclone，逐行回调 stderr+stdout
    static func run(_ args: [String], onLine: ((String) -> Void)? = nil) async -> RcloneResult {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: Settings.rclonePath)
            p.arguments = ["--config", Settings.configPath] + args
            p.environment = env
            let pipe = Pipe()
            p.standardOutput = pipe; p.standardError = pipe
            var all = ""
            var buf = Data()
            let lock = NSLock()
            pipe.fileHandleForReading.readabilityHandler = { h in
                let chunk = h.availableData
                guard !chunk.isEmpty else { return }
                lock.lock(); buf.append(chunk)
                while let nl = buf.firstIndex(of: 0x0A) {
                    let line = String(decoding: buf[buf.startIndex..<nl], as: UTF8.self)
                    buf.removeSubrange(buf.startIndex...nl)
                    all += line + "\n"
                    onLine?(line)
                }
                lock.unlock()
            }
            p.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                let rest = pipe.fileHandleForReading.readDataToEndOfFile()
                lock.lock()
                buf.append(rest)
                if !buf.isEmpty { let l = String(decoding: buf, as: UTF8.self); all += l; onLine?(l) }
                lock.unlock()
                cont.resume(returning: RcloneResult(code: proc.terminationStatus, output: all))
            }
            do { try p.run() } catch {
                cont.resume(returning: RcloneResult(code: -1, output: "无法启动 rclone：\(error.localizedDescription)"))
            }
        }
    }

    static func listRemotes() async -> (remotes: [String], error: String?) {
        let r = await run(["listremotes"])
        if r.code != 0 { return ([], r.output.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let list = r.output.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasSuffix(":") }.map { String($0.dropLast()) }
        return (list, nil)
    }
}

// MARK: - 同步引擎

@MainActor
final class SyncEngine: ObservableObject {
    enum Phase: Equatable { case idle, previewing, awaitingConfirm, syncing, done, failed }

    @Published var phase: Phase = .idle
    @Published var status = "准备就绪"
    @Published var progress: Double = 0       // 0...1
    @Published var detail = ""
    @Published var preview: (copies: Int, deletes: Int, conflicts: Int) = (0, 0, 0)
    @Published var conflictFiles: [String] = []
    @Published var lastLog = ""
    @Published var changes: [FileChange] = []   // 本次每个文件的新增/修改/删除
    @Published var toast: Toast?
    @Published var needsSetup = false   // 只有缺密码/找不到 remote 时才把用户带去设置

    static let checkFile = "RCLONE_TEST"
    var remoteRoot: String { "\(Settings.remote):\(Settings.remotePath)" }
    var needsResync: Bool { Settings.baselineKey != Settings.pairKey }

    private var backupStamp: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HHmmss"; return f.string(from: Date())
    }

    /// 本地回收区放在同步目录之外，云端回收区放在 OneDrive 根下的 _onesync_backup（目标目录不能是根，保证不重叠）
    /// 删除超过 10% 时 rclone 会中止；预览里让用户看到数量并确认后，才带 --force 真跑
    private var forceDeletes = false

    private func bisyncArgs(dryRun: Bool, resync: Bool) -> [String] {
        let stamp = backupStamp
        let localBackup = NSHomeDirectory() + "/Library/Application Support/OneSync/backup/\(stamp)"
        var a = ["bisync", Settings.localPath, remoteRoot,
                 "--conflict-resolve", "newer",
                 "--conflict-loser", "num",
                 "--conflict-suffix", "conflict",
                 "--backup-dir1", localBackup,
                 "--backup-dir2", "\(Settings.remote):_onesync_backup/\(stamp)",
                 "--max-delete", "10",
                 "--check-access", "--check-filename", Self.checkFile,
                 "--compare", "size,modtime",
                 "--resilient", "--recover",
                 "--create-empty-src-dirs",
                 "--exclude", ".DS_Store",
                 "-v", "--stats", "1s", "--stats-log-level", "NOTICE", "--use-json-log"]
        if resync { a.append("--resync") }
        if dryRun { a.append("--dry-run") }
        if forceDeletes { a.append("--force") }
        return a
    }

    /// 第一步：确保两边都有标记文件，再 dry-run 预览
    func startPreview() {
        phase = .previewing; status = "正在检查变化…"; progress = 0; detail = ""; changes = []
        Task {
            // 傻瓜式：自动挑 remote、自动建两边目录，只有缺密码才打断用户
            if Settings.remote.isEmpty {
                let r = await Rclone.listRemotes()
                guard let pick = r.remotes.first(where: { $0.lowercased().contains("onedrive") }) ?? r.remotes.first else {
                    phase = .failed; needsSetup = true
                    status = r.error != nil ? "需要先输入一次 rclone 配置密码" : "没找到 OneDrive remote"
                    return
                }
                Settings.remote = pick
            }
            try? FileManager.default.createDirectory(atPath: Settings.localPath, withIntermediateDirectories: true)
            let mk = await Rclone.run(["mkdir", remoteRoot])
            if mk.code != 0 {
                lastLog = mk.output; fail(mk.output)
                if mk.output.lowercased().contains("password") { needsSetup = true }
                return
            }
            if needsResync {
                // check-access 需要两边都有标记文件；只在建立基线时补
                _ = await Rclone.run(["touch", Settings.localPath + "/" + Self.checkFile])
                _ = await Rclone.run(["touch", remoteRoot + "/" + Self.checkFile])
            }
            forceDeletes = false
            var copies = 0, deletes = 0, conflicts = 0
            func count(_ line: String) {
                let msg = Self.message(of: line)
                if msg.contains("Queue copy") || msg.contains("Copied (new)") || msg.contains("Copied (replaced") { copies += 1 }
                if msg.contains("Queue delete") || msg.contains("Deleted") { deletes += 1 }
                if msg.lowercased().contains("conflict") && msg.contains("Path") { conflicts += 1 }
            }
            var r = await Rclone.run(bisyncArgs(dryRun: true, resync: needsResync)) { count($0) }
            if r.code != 0 && r.output.contains("too many deletes") {
                // 删除比例超标：带 --force 再预览一次拿准确数量，交给用户在确认卡片里拍板
                forceDeletes = true; copies = 0; deletes = 0; conflicts = 0
                r = await Rclone.run(bisyncArgs(dryRun: true, resync: false)) { count($0) }
            }
            lastLog = r.output
            if r.code != 0 { forceDeletes = false; fail(r.output); return }
            var list: [FileChange] = []
            for l in r.output.split(separator: "\n") { ChangeParser.apply(String(l), to: &list) }
            changes = list.map { var c = $0; c.done = false; return c }
            if !changes.isEmpty {
                conflicts = changes.filter { $0.kind == .conflict }.count
                deletes = changes.filter { $0.kind == .deleted }.count
                copies = changes.count - deletes
            }
            preview = (copies, deletes, conflicts)
            if copies == 0 && deletes == 0 {
                phase = .done; status = "两边已一致"; Settings.lastSync = Date()
                show(Toast(icon: "checkmark.seal.fill", color: .green, title: "两边已经一致", subtitle: "没有需要同步的文件"))
                if needsResync { await runReal() }   // 基线还没建立的话照样建
            } else {
                phase = .awaitingConfirm
                status = needsResync ? "首次同步：只合并，不删除任何文件"
                    : forceDeletes ? "⚠️ 删除较多（超过 10%），确认后执行，删掉的文件会进回收区" : "确认后开始同步"
            }
        }
    }

    func confirm() { Task { await runReal() } }
    func cancel() { forceDeletes = false; phase = .idle; status = "已取消" }

    private func runReal() async {
        let resync = needsResync
        phase = .syncing; status = resync ? "正在建立同步基线…" : "正在同步…"; progress = 0
        let r = await Rclone.run(bisyncArgs(dryRun: false, resync: resync)) { [weak self] line in
            let s = Self.stats(of: line)
            Task { @MainActor in
                guard let self else { return }
                if let s { self.progress = s.0; self.detail = s.1; return }
                withAnimation(.spring(duration: 0.35)) { ChangeParser.apply(line, to: &self.changes) }
            }
        }
        lastLog = r.output
        if r.code != 0 { fail(r.output); return }
        forceDeletes = false
        if resync { Settings.baselineKey = Settings.pairKey }
        Settings.lastSync = Date()
        progress = 1
        scanConflicts()
        phase = .done
        status = conflictFiles.isEmpty ? "同步完成" : "同步完成，有 \(conflictFiles.count) 个冲突副本"
        detail = ""
        for i in changes.indices { changes[i].done = true }
        show(Toast(icon: conflictFiles.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                   color: conflictFiles.isEmpty ? .green : .orange,
                   title: changes.isEmpty ? "同步完成" : "已同步 \(changes.count) 个文件",
                   subtitle: summary))
    }

    /// "新增 2 · 修改 1 · 删除 1"
    var summary: String {
        let parts: [(FileChange.Kind, String)] = [(.new, "新增"), (.modified, "修改"), (.deleted, "删除→回收区"), (.conflict, "冲突")]
        return parts.compactMap { k, t in
            let n = changes.filter { $0.kind == k }.count
            return n > 0 ? "\(t) \(n)" : nil
        }.joined(separator: " · ")
    }

    private var toastTask: Task<Void, Never>?
    func show(_ t: Toast) {
        withAnimation(.spring(duration: 0.45, bounce: 0.3)) { toast = t }
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(4.5))
            if !Task.isCancelled { withAnimation(.easeInOut(duration: 0.3)) { toast = nil } }
        }
    }

    private func fail(_ out: String) {
        forceDeletes = false
        phase = .failed
        defer { show(Toast(icon: "xmark.octagon.fill", color: .red, title: status, subtitle: "同步已中止，点「日志」看原因")) }
        let low = out.lowercased()
        if low.contains("too many deletes") || low.contains("max-delete") {
            status = "删除超过 10%，已自动中止"
        } else if low.contains("check-access") || low.contains(Self.checkFile.lowercased()) {
            status = "找不到标记文件，可能目录没挂上，已中止"
        } else if low.contains("config") && low.contains("password") {
            status = "rclone 配置密码不对或没设置"
        } else if low.contains("must run --resync") || low.contains("resync") {
            Settings.baselineKey = ""
            status = "需要重新建立基线，再点一次同步"
        } else {
            status = "同步失败，展开日志查看"
        }
        // 只留最后几行错误
        detail = out.split(separator: "\n").suffix(3).map { Self.message(of: String($0)) }.joined(separator: "\n")
    }

    func scanConflicts() {
        let root = URL(fileURLWithPath: Settings.localPath)
        var found: [String] = []
        let re = try! NSRegularExpression(pattern: #"\.conflict\d+"#)
        if let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let u as URL in e {
                let n = u.lastPathComponent
                if re.firstMatch(in: n, range: NSRange(n.startIndex..., in: n)) != nil {
                    found.append(u.path.replacingOccurrences(of: root.path + "/", with: ""))
                }
            }
        }
        conflictFiles = found
    }

    // JSON 日志：取 msg 字段
    nonisolated static func message(of line: String) -> String {
        guard let d = line.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let m = o["msg"] as? String else { return line }
        return m.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // stats 日志 → (进度, "12.3 MB / 40 MB · 3/10 个文件")
    nonisolated static func stats(of line: String) -> (Double, String)? {
        guard let d = line.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let s = o["stats"] as? [String: Any] else { return nil }
        let bytes = (s["bytes"] as? Double) ?? 0
        let total = (s["totalBytes"] as? Double) ?? 0
        let n = (s["transfers"] as? Int) ?? 0
        let tn = (s["totalTransfers"] as? Int) ?? 0
        let p = total > 0 ? bytes / total : (tn > 0 ? Double(n) / Double(tn) : 0)
        let f = ByteCountFormatter()
        return (min(p, 1), "\(f.string(fromByteCount: Int64(bytes))) / \(f.string(fromByteCount: Int64(total))) · \(n)/\(tn) 个文件")
    }
}
