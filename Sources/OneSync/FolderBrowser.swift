import SwiftUI

// MARK: - 文件夹外观：按名字挑图标和颜色，让一屏文件夹一眼能分清

enum FolderLook {
    static let palette: [Color] = [.blue, .teal, .indigo, .orange, .pink, .purple, .green, .mint, .cyan, .red, .yellow, .brown]

    static func color(_ name: String) -> Color {
        var h: UInt32 = 5381
        for b in name.utf8 { h = (h &* 33) ^ UInt32(b) }
        return palette[Int(h % UInt32(palette.count))]
    }

    /// 文件夹上的小徽标：常见名字给语义图标，其他按哈希挑一个
    static func badge(_ name: String) -> String {
        let n = name.lowercased()
        let rules: [([String], String)] = [
            (["desktop", "桌面"], "menubar.dock.rectangle"),
            (["document", "doc", "文档"], "doc.text.fill"),
            (["picture", "photo", "image", "相册", "图片", "照片", "screenshot"], "photo.fill"),
            (["music", "音乐", "audio"], "music.note"),
            (["video", "movie", "视频"], "film.fill"),
            (["download", "下载"], "arrow.down.circle.fill"),
            (["csc", "course", "school", "课程", "作业", "lecture", "mat", "sta"], "graduationcap.fill"),
            (["code", "project", "dev", "github", "src"], "chevron.left.forwardslash.chevron.right"),
            (["sync", "rime", "备份", "backup"], "arrow.triangle.2.circlepath"),
            (["3d", "model", "reconstruction"], "cube.fill"),
            (["book", "note", "笔记", "obsidian"], "book.closed.fill"),
            (["work", "工作", "office"], "briefcase.fill"),
            (["game", "游戏"], "gamecontroller.fill"),
            (["attach", "附件", "share", "共享"], "paperclip"),
        ]
        for (keys, sym) in rules where keys.contains(where: n.contains) { return sym }
        let generic = ["star.fill", "heart.fill", "leaf.fill", "bolt.fill", "sparkles", "moon.fill", "flame.fill", "tag.fill", "paperplane.fill", "lightbulb.fill"]
        var h: UInt32 = 7
        for b in name.utf8 { h = (h &* 31) &+ UInt32(b) }
        return generic[Int(h % UInt32(generic.count))]
    }
}

/// 一个彩色文件夹图标：渐变底 + 白色徽标
struct FolderIcon: View {
    var name: String
    var size: CGFloat = 54
    var body: some View {
        let c = FolderLook.color(name)
        ZStack {
            Image(systemName: "folder.fill")
                .resizable().scaledToFit()
                .foregroundStyle(LinearGradient(colors: [c.opacity(0.75), c], startPoint: .top, endPoint: .bottom))
                .shadow(color: c.opacity(0.35), radius: 6, y: 3)
            Image(systemName: FolderLook.badge(name))
                .font(.system(size: size * 0.28, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .offset(y: size * 0.06)
        }
        .frame(width: size, height: size * 0.82)
    }
}

// MARK: - OneDrive 文件夹浏览器

struct FolderBrowser: View {
    var remote: String
    @Binding var selection: String
    var close: () -> Void

    @State private var path: [String] = []          // 当前所在路径的各级
    @State private var folders: [String] = []
    @State private var loading = false
    @State private var error = ""
    @State private var forward = true                // 进/退的动画方向
    @State private var hovered: String?
    @State private var creating = false
    @State private var newName = ""

    private var current: String { path.joined(separator: "/") }
    private let cols = [GridItem(.adaptive(minimum: 92), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            breadcrumb
            content
                .frame(height: 300)
                .glassCard()
            footer
        }
        .padding(.horizontal, 18).padding(.bottom, 18).padding(.top, 30)
        .task {
            // 打开时直接定位到已选的目录
            path = selection.split(separator: "/").map(String.init)
            await load()
        }
    }

    var header: some View {
        HStack {
            Button { close() } label: {
                Label("返回", systemImage: "chevron.left").font(.callout.weight(.medium))
            }.buttonStyle(.plain)
            Spacer()
            Text("选择 OneDrive 文件夹").font(.system(size: 17, weight: .semibold))
            Spacer()
            Button { withAnimation(.spring(duration: 0.3)) { creating.toggle() } } label: {
                Image(systemName: "folder.badge.plus").font(.system(size: 16))
            }.buttonStyle(.plain).help("新建文件夹")
        }
    }

    var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                crumb("OneDrive", icon: "cloud.fill", depth: 0)
                ForEach(Array(path.enumerated()), id: \.offset) { i, p in
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Color.primary.opacity(0.4))
                    crumb(p, icon: nil, depth: i + 1)
                }
            }
            .animation(.spring(duration: 0.35), value: path)
        }
    }

    func crumb(_ title: String, icon: String?, depth: Int) -> some View {
        let isLast = depth == path.count
        return Button { go(to: depth) } label: {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon) }
                Text(title).lineLimit(1)
            }
            .font(.callout.weight(isLast ? .semibold : .regular))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(isLast ? Color.accentColor.opacity(0.15) : .clear, in: Capsule())
            .foregroundStyle(isLast ? Color.accentColor : Color.primary.opacity(0.75))
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    @ViewBuilder var content: some View {
        ZStack {
            if loading {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.regular)
                    Text("正在读取…").font(.callout).foregroundStyle(Color.primary.opacity(0.6))
                }.transition(.opacity)
            } else if !error.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.icloud").font(.system(size: 34)).foregroundStyle(.orange)
                    Text(error).font(.callout).multilineTextAlignment(.center).lineLimit(4)
                    Button("重试") { Task { await load() } }
                }.padding().transition(.opacity)
            } else {
                ScrollView {
                    if creating { newFolderRow.padding([.horizontal, .top], 12).transition(.move(edge: .top).combined(with: .opacity)) }
                    if folders.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "folder").font(.system(size: 36)).foregroundStyle(Color.primary.opacity(0.3))
                            Text("这里没有子文件夹").font(.callout).foregroundStyle(Color.primary.opacity(0.6))
                        }.frame(maxWidth: .infinity).padding(.top, 70)
                    }
                    LazyVGrid(columns: cols, spacing: 14) {
                        ForEach(Array(folders.enumerated()), id: \.element) { i, f in
                            tile(f, index: i)
                        }
                    }
                    .padding(12)
                }
                .id(current)   // 换目录时整个网格做转场
                .transition(.asymmetric(
                    insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            }
        }
        .clipped()
        .animation(.spring(duration: 0.4, bounce: 0.15), value: current)
        .animation(.easeInOut(duration: 0.2), value: loading)
    }

    func tile(_ name: String, index: Int) -> some View {
        let isHover = hovered == name
        return Button { enter(name) } label: {
            VStack(spacing: 6) {
                FolderIcon(name: name)
                    .scaleEffect(isHover ? 1.08 : 1)
                    .rotationEffect(.degrees(isHover ? -3 : 0))
                Text(name).font(.callout).lineLimit(2).multilineTextAlignment(.center)
                    .frame(height: 34, alignment: .top)
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(isHover ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { h in withAnimation(.spring(duration: 0.25, bounce: 0.4)) { hovered = h ? name : (hovered == name ? nil : hovered) } }
        .modifier(StaggerIn(index: index))
        .help("打开 \(name)")
    }

    var newFolderRow: some View {
        HStack {
            FolderIcon(name: newName.isEmpty ? "new" : newName, size: 30)
            TextField("新文件夹名称", text: $newName).textFieldStyle(.roundedBorder).onSubmit { create() }
            Button("创建") { create() }.disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    var footer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: path.isEmpty ? "info.circle" : "checkmark.circle.fill")
                    .foregroundStyle(path.isEmpty ? Color.orange : Color.green)
                    .contentTransition(.symbolEffect(.replace))
                Text(path.isEmpty ? "根目录不能用来同步，请点开一个文件夹" : "将同步到：OneDrive/\(current)")
                    .font(.callout).lineLimit(1).truncationMode(.middle)
                Spacer()
            }
            .animation(.easeInOut(duration: 0.2), value: path.isEmpty)
            Button {
                selection = current
                close()
            } label: {
                Text(path.isEmpty ? "请先打开一个文件夹" : "选择「\(path.last ?? "")」")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(path.isEmpty)
        }
    }

    // MARK: 行为

    func enter(_ name: String) {
        forward = true
        path.append(name)
        Task { await load() }
    }

    func go(to depth: Int) {
        guard depth < path.count else { return }
        forward = false
        path = Array(path.prefix(depth))
        Task { await load() }
    }

    func load() async {
        loading = true; error = ""
        let target = "\(remote):\(current)"
        let r = await Rclone.run(["lsf", target, "--dirs-only", "--max-depth", "1"])
        if r.code != 0 {
            let lines = r.output.split(separator: "\n").map { SyncEngine.message(of: String($0)) }
            if r.output.contains("directory not found") && !path.isEmpty {
                // 之前选的目录还不存在（比如默认的 OneSync），退回上一级
                path.removeLast(); await load(); return
            }
            error = lines.last ?? "读取失败"
            folders = []
        } else {
            folders = r.output.split(separator: "\n")
                .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) }
                .filter { !$0.isEmpty && !$0.hasPrefix("_onesync_backup") }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
        withAnimation(.easeOut(duration: 0.2)) { loading = false }
    }

    func create() {
        let n = newName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        Task {
            let target = "\(remote):" + (path + [n]).joined(separator: "/")
            let r = await Rclone.run(["mkdir", target])
            if r.code == 0 {
                newName = ""
                withAnimation(.spring(duration: 0.3)) { creating = false }
                enter(n)
            } else {
                error = SyncEngine.message(of: String(r.output.split(separator: "\n").last ?? "创建失败"))
            }
        }
    }
}

/// 按下时轻微缩小，松开回弹
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(duration: 0.2, bounce: 0.5), value: configuration.isPressed)
    }
}

/// 网格里的文件夹依次弹出
struct StaggerIn: ViewModifier {
    var index: Int
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.7)
            .offset(y: shown ? 0 : 8)
            .onAppear {
                withAnimation(.spring(duration: 0.45, bounce: 0.35).delay(Double(min(index, 20)) * 0.025)) { shown = true }
            }
    }
}
