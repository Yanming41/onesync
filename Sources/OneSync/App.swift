import SwiftUI
import AppKit

@main
struct OneSyncApp: App {
    @StateObject private var engine = SyncEngine()

    /// 测试用：`OneSync --rclone <参数…>` 用钥匙串里的密码直接跑 rclone 然后退出
    init() {
        let args = CommandLine.arguments
        if args.count > 1, args[1] == "--keychain-check" {   // 只报有没有、长度，不输出密码
            print(Keychain.get().map { "present len=\($0.count)" } ?? "missing"); exit(0)
        }
        if args.count > 1, args[1] == "--rclone" {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: Settings.rclonePath)
            p.arguments = ["--config", Settings.configPath] + Array(args.dropFirst(2))
            p.environment = Rclone.env
            try? p.run(); p.waitUntilExit()
            exit(p.terminationStatus)
        }
    }

    var body: some Scene {
        // 小窗：透明标题栏 + 窗口背后毛玻璃（能透出桌面），常驻最前
        Window("OneSync", id: "main") {
            RootView().environmentObject(engine)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)

        // 菜单栏图标：打开小窗 / 同步 / 退出
        MenuBarExtra {
            MenuContent().environmentObject(engine)
        } label: {
            Image(systemName: engine.phase == .syncing ? "arrow.triangle.2.circlepath.icloud.fill"
                  : engine.phase == .failed ? "exclamationmark.icloud" : "arrow.triangle.2.circlepath.icloud")
        }
    }
}

struct MenuContent: View {
    @EnvironmentObject var e: SyncEngine
    @Environment(\.openWindow) var openWindow
    var body: some View {
        Button("打开 OneSync") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button("立即同步") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true); e.startPreview() }
            .disabled(e.phase == .syncing || e.phase == .previewing)
        Divider()
        Button("退出") { NSApp.terminate(nil) }
    }
}

/// 把所在 NSWindow 设成透明，并铺一层 behind-window 的系统毛玻璃
enum GlassStyle: String, CaseIterable, Identifiable {
    case liquid, frosted, clear
    var id: String { rawValue }
    var title: String {
        switch self { case .liquid: "液态玻璃（官方白透）"; case .frosted: "磨砂玻璃"; case .clear: "超透明" }
    }
    static var current: GlassStyle { GlassStyle(rawValue: UserDefaults.standard.string(forKey: "glassStyle") ?? "") ?? .liquid }
    /// 液态玻璃需要 macOS 26，旧系统自动退回磨砂
    var effective: GlassStyle {
        if self == .liquid, #unavailable(macOS 26) { return .frosted }
        return self
    }
}

/// 把所在 NSWindow 设成透明；磨砂/超透风格铺一层 behind-window 毛玻璃，液态玻璃交给 SwiftUI glassEffect
struct GlassWindow: NSViewRepresentable {
    var style: GlassStyle
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.state = .active
        apply(v)
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.isOpaque = false
            w.backgroundColor = .clear
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.styleMask.insert(.fullSizeContentView)   // 内容铺到标题栏下面，去掉那块灰框
            w.titlebarSeparatorStyle = .none
            w.toolbar = nil
            w.hasShadow = false                        // 窗口矩形的阴影/边框也不要，只留面板自己的
            if let frameView = w.contentView?.superview {
                frameView.wantsLayer = true
                frameView.layer?.backgroundColor = NSColor.clear.cgColor
            }
            // 红绿灯挪进面板左上角
            if let close = w.standardWindowButton(.closeButton) {
                close.setFrameOrigin(NSPoint(x: 18, y: close.frame.origin.y - 8))
            }
            w.isMovableByWindowBackground = true
            w.level = .floating
            w.standardWindowButton(.miniaturizeButton)?.isHidden = true
            w.standardWindowButton(.zoomButton)?.isHidden = true
        }
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { apply(v) }
    private func apply(_ v: NSVisualEffectView) {
        switch style.effective {
        case .liquid:  v.alphaValue = 0          // 不画，用液态玻璃
        case .frosted: v.material = .popover; v.alphaValue = 1
        case .clear:   v.material = .underWindowBackground; v.alphaValue = 0.55
        }
    }
}

extension View {
    /// 整个面板的底：液态玻璃时用系统 glassEffect
    @ViewBuilder func panelGlass(_ s: GlassStyle) -> some View {
        if #available(macOS 26, *), s.effective == .liquid {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        } else { self }
    }
    @ViewBuilder func glassCard() -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        if #available(macOS 26, *), GlassStyle.current.effective == .liquid {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(Color(nsColor: .windowBackgroundColor).opacity(0.55), in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
        }
    }
    @ViewBuilder func glassCircle() -> some View {
        if #available(macOS 26, *), GlassStyle.current.effective == .liquid {
            self.glassEffect(.regular.interactive(), in: Circle())
        } else {
            self.background(Circle().fill(.white.opacity(0.14)).overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1)))
        }
    }
}

struct RootView: View {
    @AppStorage("glassStyle") var style = GlassStyle.liquid.rawValue
    @AppStorage("colorMode") var colorMode = "light"
    @State private var showSettings = false   // 放在这里，切换风格重建面板时设置页不会被关掉
    var body: some View {
        let s = GlassStyle(rawValue: style) ?? .liquid
        PanelView(showSettings: $showSettings)
            .panelGlass(s)
            .background(GlassWindow(style: s))
            .ignoresSafeArea()
            .preferredColorScheme(colorMode == "light" ? .light : colorMode == "dark" ? .dark : nil)
            .id(style + colorMode)   // 切换风格时整体重建
    }
}

// MARK: - 主面板

struct PanelView: View {
    @EnvironmentObject var e: SyncEngine
    @Binding var showSettings: Bool
    @State private var showLog = false
    @State private var showChanges = false

    var body: some View {
        ZStack {
            if showSettings {
                SettingsView(done: { showSettings = false; if e.phase == .failed { e.startPreview() } })
            } else {
                main
            }
        }
        .frame(width: 360)
        .onChange(of: e.needsSetup) { _, v in if v { showSettings = true; e.needsSetup = false } }
    }

    var main: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("OneSync").font(.system(size: 19, weight: .semibold))
                    Text(pairText).font(.callout).foregroundStyle(Color.primary.opacity(0.72)).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button { showSettings = true } label: { Image(systemName: "gearshape") }.buttonStyle(.plain)
            }

            SyncButton().padding(.vertical, 6)

            Text(e.status).font(.system(size: 16, weight: .medium)).multilineTextAlignment(.center)
                .contentTransition(.interpolate)
                .id(e.status).transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))

            if e.phase == .syncing {
                ProgressView(value: e.progress).progressViewStyle(.linear).tint(.blue)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
            if !e.detail.isEmpty {
                Text(e.detail).font(.callout).foregroundStyle(Color.primary.opacity(0.72)).multilineTextAlignment(.center).lineLimit(4)
                    .contentTransition(.numericText())
            }

            if e.phase == .awaitingConfirm { confirmCard.transition(.card) }
            if e.phase == .syncing && !e.changes.isEmpty {
                ChangeList(list: e.changes, showDone: true).padding(8).glassCard().transition(.card)
            }
            if e.phase == .done && !e.changes.isEmpty { doneCard.transition(.card) }

            if !e.conflictFiles.isEmpty { conflictCard.transition(.card) }

            HStack {
                Text(lastText).font(.footnote).foregroundStyle(Color.primary.opacity(0.6))
                Spacer()
                if !e.lastLog.isEmpty {
                    Button(showLog ? "收起日志" : "日志") { showLog.toggle() }.font(.footnote).buttonStyle(.plain).foregroundStyle(Color.primary.opacity(0.72))
                }
            }
            if showLog {
                ScrollView {
                    Text(e.lastLog.split(separator: "\n").suffix(80).map { SyncEngine.message(of: String($0)) }.joined(separator: "\n"))
                        .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 140).glassCard()
            }
        }
        .padding(.horizontal, 18).padding(.bottom, 18).padding(.top, 30)
        .animation(.spring(duration: 0.45, bounce: 0.2), value: e.phase)
        .animation(.spring(duration: 0.35), value: e.status)
        .animation(.spring(duration: 0.35), value: showChanges)
        .animation(.spring(duration: 0.35), value: showLog)
        .overlay(alignment: .top) {
            if let t = e.toast {
                ToastView(t: t)
                    .padding(.horizontal, 14).padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.9, anchor: .top)))
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.25)) { e.toast = nil } }
            }
        }
    }

    var doneCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { showChanges.toggle() } label: {
                HStack {
                    ChangeChips(list: e.changes)
                    Spacer()
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(showChanges ? 180 : 0))
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if showChanges {
                ChangeList(list: e.changes, showDone: true).transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10).glassCard()
    }

    var confirmCard: some View {
        VStack(spacing: 10) {
            if e.changes.isEmpty {
                HStack(spacing: 18) {
                    stat("\(e.preview.copies)", "传输", "arrow.up.arrow.down")
                    stat("\(e.preview.deletes)", "删除→回收区", "trash")
                    stat("\(e.preview.conflicts)", "冲突", "exclamationmark.triangle")
                }
            } else {
                ChangeChips(list: e.changes).frame(maxWidth: .infinity, alignment: .leading)
                ChangeList(list: e.changes)
            }
            HStack {
                Button("取消") { e.cancel() }.buttonStyle(.bordered)
                Button("开始同步") { e.confirm() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }.controlSize(.regular)
        }
        .padding(12).glassCard()
    }

    var conflictCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("冲突副本（旧版本已改名保留）", systemImage: "doc.on.doc").font(.callout.weight(.semibold))
            ForEach(e.conflictFiles.prefix(5), id: \.self) { f in
                Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: Settings.localPath + "/" + f)]) } label: {
                    Text(f).font(.footnote).lineLimit(1).truncationMode(.middle)
                }.buttonStyle(.plain).foregroundStyle(.blue)
            }
            if e.conflictFiles.count > 5 { Text("还有 \(e.conflictFiles.count - 5) 个…").font(.footnote).foregroundStyle(Color.primary.opacity(0.72)) }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(10).glassCard()
    }

    func stat(_ n: String, _ t: String, _ icon: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon).font(.callout).foregroundStyle(Color.primary.opacity(0.72))
            Text(n).font(.system(size: 22, weight: .semibold, design: .rounded))
            Text(t).font(.footnote).foregroundStyle(Color.primary.opacity(0.72))
        }
    }

    var pairText: String {
        "\((Settings.localPath as NSString).abbreviatingWithTildeInPath) ⇄ OneDrive/\(Settings.remotePath)"
    }
    var lastText: String {
        guard let d = Settings.lastSync else { return "从未同步" }
        let f = RelativeDateTimeFormatter(); f.locale = Locale(identifier: "zh_CN")
        return "上次同步 " + f.localizedString(for: d, relativeTo: Date())
    }
}

// MARK: - 大圆按钮

struct SyncButton: View {
    @EnvironmentObject var e: SyncEngine
    @State private var spin = false
    var busy: Bool { e.phase == .previewing || e.phase == .syncing }

    var body: some View {
        Button { if !busy { e.startPreview() } } label: {
            ZStack {
                Color.clear.glassCircle()
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                if e.phase == .syncing {
                    Circle().trim(from: 0, to: max(e.progress, 0.02))
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90)).padding(4)
                        .animation(.easeOut, value: e.progress)
                }
                Image(systemName: icon)
                    .font(.system(size: 42, weight: .medium))
                    .contentTransition(.symbolEffect(.replace.downUp))
                    .symbolEffect(.bounce, value: e.phase == .done)
                    .foregroundStyle(e.phase == .failed ? AnyShapeStyle(.orange) : AnyShapeStyle(.blue.gradient))
                    .rotationEffect(.degrees(busy && spin ? 360 : 0))
                    .animation(busy ? .linear(duration: 1.2).repeatForever(autoreverses: false) : .default, value: spin)
            }
            .frame(width: 124, height: 124)
        }
        .buttonStyle(PressableStyle())
        .disabled(busy || e.phase == .awaitingConfirm)
        .onChange(of: busy) { _, b in spin = b }
    }

    var icon: String {
        switch e.phase {
        case .done: return "checkmark"
        case .failed: return "exclamationmark.arrow.triangle.2.circlepath"
        default: return "arrow.triangle.2.circlepath"
        }
    }
}

// MARK: - 设置页

struct SettingsView: View {
    var done: () -> Void
    @State private var password = ""
    @State private var remotes: [String] = []
    @State private var remote = Settings.remote
    @State private var local = Settings.localPath
    @State private var remotePath = Settings.remotePath
    @State private var msg = ""
    @State private var pwMsg = ""
    @State private var browsing = false
    @AppStorage("glassStyle") var style = GlassStyle.liquid.rawValue
    @AppStorage("colorMode") var colorMode = "light"

    var body: some View {
        ZStack {
            if browsing {
                FolderBrowser(remote: remote, selection: $remotePath) {
                    withAnimation(.spring(duration: 0.45, bounce: 0.2)) { browsing = false }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                form.transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
    }

    var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("设置").font(.system(size: 19, weight: .semibold))

            if Settings.isEncrypted(Settings.configPath) {
            group("rclone 配置密码") {
                HStack {
                    SecureField(Keychain.get() == nil ? "配置已加密，输入密码" : "已保存在钥匙串", text: $password)
                        .textFieldStyle(.roundedBorder)
                    Button("解锁") { unlock() }.disabled(password.isEmpty)
                }
                if !pwMsg.isEmpty { Text(pwMsg).font(.footnote).foregroundStyle(pwMsg.hasPrefix("✓") ? .green : .red) }
            }

            }

            group("OneDrive remote") {
                if remotes.isEmpty {
                    Text(msg.isEmpty ? "读取中…" : msg).font(.callout).foregroundStyle(Color.primary.opacity(0.72)).lineLimit(3)
                } else {
                    Picker("", selection: $remote) { ForEach(remotes, id: \.self) { Text($0).tag($0) } }.labelsHidden()
                }
            }

            group("本地目录") {
                HStack {
                    Text(local.isEmpty ? "未选择" : local).font(.callout).lineLimit(1).truncationMode(.head)
                    Spacer()
                    Button("选择…") { pickFolder() }
                }
            }

            group("外观") {
                Picker("", selection: $style) {
                    ForEach(GlassStyle.allCases) { Text($0.title).tag($0.rawValue) }
                }.labelsHidden().pickerStyle(.radioGroup)
                Picker("", selection: $colorMode) {
                    Text("白色").tag("light"); Text("深色").tag("dark"); Text("跟随系统").tag("system")
                }.labelsHidden().pickerStyle(.segmented)
            }

            group("OneDrive 目录") {
                Button {
                    withAnimation(.spring(duration: 0.45, bounce: 0.2)) { browsing = true }
                } label: {
                    HStack(spacing: 10) {
                        FolderIcon(name: remotePath.split(separator: "/").last.map(String.init) ?? "OneSync", size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(remotePath.split(separator: "/").last.map(String.init) ?? "未选择").font(.body.weight(.medium))
                            Text("OneDrive/\(remotePath)").font(.caption).foregroundStyle(Color.primary.opacity(0.6)).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Text("浏览").font(.callout)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Color.primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .disabled(remotes.isEmpty)
            }

            Text("改目录后，下次同步会先只合并、不删除，重新建立基线。").font(.footnote).foregroundStyle(Color.primary.opacity(0.72))

            HStack {
                Spacer()
                Button("返回") { done() }
                Button("保存") { save() }.buttonStyle(.borderedProminent).disabled(!canSave)
            }
        }
        .padding(.horizontal, 18).padding(.bottom, 18).padding(.top, 30)
        .task { await load() }
    }

    var canSave: Bool {
        let rp = remotePath.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        return !remote.isEmpty && !local.isEmpty && !rp.isEmpty
    }

    /// 存之前先用 rclone 验证密码，错的不保存
    func unlock() {
        let pw = password
        pwMsg = "验证中…"
        Task {
            Rclone.overridePassword = pw
            let r = await Rclone.listRemotes()
            Rclone.overridePassword = nil
            if r.error != nil {
                pwMsg = "密码不对，rclone 解不开配置"
            } else if !Keychain.set(pw) {
                pwMsg = "密码正确，但写不进钥匙串：请在「钥匙串访问」里删掉名为「\((Bundle.main.bundleIdentifier ?? "io.github.onesync")).rclone-config」的条目再试"
            } else {
                password = ""; pwMsg = "✓ 密码正确，已保存"
                await load()
            }
        }
    }

    func save() {
        Settings.remote = remote
        Settings.localPath = local
        Settings.remotePath = remotePath.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        done()
    }

    func load() async {
        let r = await Rclone.listRemotes()
        remotes = r.remotes
        msg = r.error.map { $0.lowercased().contains("password") ? "需要先输入 rclone 配置密码" : $0 } ?? (r.remotes.isEmpty ? "没有找到 remote" : "")
        if remote.isEmpty || !remotes.contains(remote) {
            remote = remotes.first { $0.lowercased().contains("onedrive") } ?? remotes.first ?? ""
        }
    }

    func pickFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        if p.runModal() == .OK, let u = p.url { local = u.path }
    }

    func group<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.callout.weight(.medium)).foregroundStyle(Color.primary.opacity(0.72))
            c()
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }
}


extension AnyTransition {
    /// 卡片出现：从上方轻轻落下 + 渐显；消失：缩小渐隐
    static var card: AnyTransition {
        .asymmetric(insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.96, anchor: .top)),
                    removal: .opacity.combined(with: .scale(scale: 0.96)))
    }
}
