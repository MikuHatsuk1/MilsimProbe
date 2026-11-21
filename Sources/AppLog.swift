import Foundation
import UIKit

/// 屏幕日志：没有 Xcode 时靠它调试。所有修改都在主线程进行。
final class AppLog: ObservableObject {
    static let shared = AppLog()

    @Published private(set) var lines: [String] = []

    private let maxLines = 3000
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    func add(_ tag: String, _ message: String) {
        let line = "\(formatter.string(from: Date())) [\(tag)] \(message)"
        print(line)
        if Thread.isMainThread {
            append(line)
        } else {
            DispatchQueue.main.async { self.append(line) }
        }
    }

    private func append(_ line: String) {
        lines.append(line)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }

    func clear() {
        lines.removeAll()
    }

    /// 导出为文本文件，弹出系统分享面板（可存到“文件”或发给自己）。
    func share() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("milsim-probe-log.txt")
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        } catch {
            add("LOG", "导出失败: \(error.localizedDescription)")
            return
        }
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first,
              var top = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
                ?? scene.windows.first?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = top.view
        top.present(vc, animated: true)
    }
}
