import SwiftUI

// MARK: - 单个文件变化：从 bisync 日志里解析

struct FileChange: Identifiable, Equatable {
    enum Kind { case new, modified, deleted, conflict }
    var path: String
    var kind: Kind
    /// true = 本地发生的变化（要传到云端）；false = 云端的变化（要拉到本地）；nil = 首次合并，方向不明
    var fromLocal: Bool?
    var done = false
    var id: String { path }

    var name: String { (path as NSString).lastPathComponent }
    var folder: String { let d = (path as NSString).deletingLastPathComponent; return d.isEmpty ? "" : d + "/" }

    var color: Color {
        switch kind { case .new: .green; case .modified: .blue; case .deleted: .red; case .conflict: .orange }
    }
    var icon: String {
        switch kind { case .new: "plus"; case .modified: "pencil"; case .deleted: "trash"; case .conflict: "exclamationmark" }
    }
    var verb: String {
        switch kind { case .new: "新增"; case .modified: "修改"; case .deleted: "删除"; case .conflict: "冲突" }
    }
    /// 这条变化会怎么处理，一句话
    var action: String {
        switch (kind, fromLocal) {
        case (.deleted, true?):  return "云端那份移进回收区"
        case (.deleted, false?): return "本地那份移进回收区"
        case (.conflict, _):     return "保留较新的，另一份改名"
        case (_, true?):         return "上传到 OneDrive"
        case (_, false?):        return "下载到本地"
        default:                 return "合并到两边"
        }
    }
    var arrow: String {
        switch fromLocal { case true?: "icloud.and.arrow.up"; case false?: "icloud.and.arrow.down"; default: "arrow.left.arrow.right" }
    }
}

enum ChangeParser {
    private static let ansi = try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;]*m")
    static func strip(_ s: String) -> String {
        ansi.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
    }

    /// "- Path1    File is new    - a/b.txt" → (本地?, 种类, 路径)
    static func delta(_ line: String) -> (Bool, FileChange.Kind, String)? {
        let m = strip(SyncEngine.message(of: line))
        guard m.hasPrefix("- Path") else { return nil }
        let local = m.hasPrefix("- Path1")
        let kind: FileChange.Kind
        if m.contains("File is new") { kind = .new }
        else if m.contains("File changed") { kind = .modified }
        else if m.contains("File was deleted") { kind = .deleted }
        else { return nil }
        guard let r = m.range(of: " - ", options: .backwards) else { return nil }
        let path = m[r.upperBound...].trimmingCharacters(in: .whitespaces)
        return path.isEmpty || path == SyncEngine.checkFile ? nil : (local, kind, path)
    }

    /// 完成的传输："Copied (...)" / "Deleted" 行带 object 字段
    static func finished(_ line: String) -> String? {
        guard let d = line.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let msg = o["msg"] as? String, let obj = o["object"] as? String,
              msg.hasPrefix("Copied") || msg.hasPrefix("Deleted") || msg.hasPrefix("Moved") else { return nil }
        return obj == SyncEngine.checkFile ? nil : obj
    }

    /// 把一行合并进列表；两边都改了同一个文件 → 冲突
    static func apply(_ line: String, to list: inout [FileChange]) {
        if let (local, kind, path) = delta(line) {
            if let i = list.firstIndex(where: { $0.path == path }) {
                if list[i].fromLocal != local { list[i].kind = .conflict; list[i].fromLocal = nil }
            } else {
                list.append(FileChange(path: path, kind: kind, fromLocal: local))
            }
        } else if let obj = finished(line) {
            if let i = list.firstIndex(where: { $0.path == obj }) { list[i].done = true }
            else { list.append(FileChange(path: obj, kind: .new, fromLocal: nil, done: true)) }   // 首次合并
        }
    }
}

// MARK: - 视图

/// 一行变化：彩色圆标 + 文件名 + 去向；完成后右侧打勾
struct ChangeRow: View {
    var c: FileChange
    var showDone = false
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(c.color.gradient)
                Image(systemName: c.icon).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 24, height: 24)
            .shadow(color: c.color.opacity(0.35), radius: 3, y: 1)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 0) {
                    Text(c.folder).foregroundStyle(Color.primary.opacity(0.5))
                    Text(c.name).foregroundStyle(Color.primary)
                }
                .font(.callout).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 4) {
                    Image(systemName: c.arrow)
                    Text("\(c.verb) · \(c.action)")
                }
                .font(.caption).foregroundStyle(c.color.opacity(0.9))
            }
            Spacer(minLength: 4)
            if showDone {
                Image(systemName: c.done ? "checkmark.circle.fill" : "circle.dotted")
                    .font(.system(size: 16))
                    .foregroundStyle(c.done ? Color.green : Color.primary.opacity(0.3))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: c.done)
            }
        }
        .padding(.vertical, 3)
        .help(c.path)
    }
}

/// 一排计数小胶囊：+3 ✎2 −1 ⚠1，数字变化时滚动
struct ChangeChips: View {
    var list: [FileChange]
    var body: some View {
        HStack(spacing: 6) {
            chip(.new, "新增"); chip(.modified, "修改"); chip(.deleted, "删除"); chip(.conflict, "冲突")
        }
    }
    @ViewBuilder func chip(_ k: FileChange.Kind, _ t: String) -> some View {
        let n = list.filter { $0.kind == k }.count
        if n > 0 {
            let sample = FileChange(path: "", kind: k, fromLocal: nil)
            HStack(spacing: 4) {
                Image(systemName: sample.icon).font(.system(size: 10, weight: .bold))
                Text("\(t) \(n)").contentTransition(.numericText(value: Double(n)))
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(sample.color)
            .background(sample.color.opacity(0.13), in: Capsule())
            .transition(.scale.combined(with: .opacity))
        }
    }
}

/// 变化列表：依次滑入，同步时最新完成的滚到可见
struct ChangeList: View {
    var list: [FileChange]
    var showDone = false
    var maxHeight: CGFloat = 170
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, c in
                        ChangeRow(c: c, showDone: showDone).id(c.id)
                            .modifier(SlideIn(index: i))
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(maxHeight: min(maxHeight, CGFloat(list.count) * 44 + 6))
            .onChange(of: list.filter(\.done).count) { _, _ in
                if showDone, let next = list.first(where: { !$0.done }) ?? list.last {
                    withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(next.id, anchor: .center) }
                }
            }
        }
    }
}

struct SlideIn: ViewModifier {
    var index: Int
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(x: shown ? 0 : 18)
            .onAppear {
                withAnimation(.spring(duration: 0.4, bounce: 0.25).delay(Double(min(index, 12)) * 0.035)) { shown = true }
            }
    }
}

/// 顶部弹出的提示条，几秒后自动收起
struct Toast: Equatable {
    var icon: String
    var color: Color
    var title: String
    var subtitle: String
}

struct ToastView: View {
    var t: Toast
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: t.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(t.color.gradient)
                .symbolEffect(.bounce, value: t.title)
            VStack(alignment: .leading, spacing: 1) {
                Text(t.title).font(.callout.weight(.semibold))
                if !t.subtitle.isEmpty {
                    Text(t.subtitle).font(.caption).foregroundStyle(Color.primary.opacity(0.65)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glassCard()
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}
