//  AccessibilityDump.swift
//  NOOP · DEBUG-only: `--ax-dump [seconds]` writes the app's accessibility tree to
//  Documents/ax-dump.txt, so VoiceOver labels can be checked from the simulator's data container.

#if DEBUG
import Darwin
import UIKit

enum AccessibilityDump {
    static func scheduleIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--ax-dump") else { return }
        // SwiftUI builds its accessibility tree only when an assistive client is attached; UI-test
        // frameworks switch the automation client on the same way.
        if let lib = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
           let sym = dlsym(lib, "_AXSSetAutomationEnabled") {
            typealias SetEnabled = @convention(c) (Int32) -> Void
            unsafeBitCast(sym, to: SetEnabled.self)(1)
        }
        let delay = args.indices.contains(i + 1) ? Double(args[i + 1]) ?? 6 : 6
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { write() }
    }

    private static func write() {
        var lines: [String] = []
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { !$0.isHidden }
        for window in windows {
            lines.append("# window \(type(of: window)) level \(window.windowLevel.rawValue)")
            walk(window, depth: 0, into: &lines)
        }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ax-dump.txt")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func walk(_ node: NSObject, depth: Int, into lines: inout [String]) {
        guard depth < 60 else { return }
        if node.accessibilityElementsHidden { return }
        if let view = node as? UIView, view.isHidden || view.alpha == 0 { return }
        if node.isAccessibilityElement {
            var parts = ["\(String(repeating: "  ", count: min(depth, 12)))•"]
            if let l = node.accessibilityLabel, !l.isEmpty { parts.append("label=\"\(l)\"") }
            if let v = node.accessibilityValue, !v.isEmpty { parts.append("value=\"\(v)\"") }
            if let h = node.accessibilityHint, !h.isEmpty { parts.append("hint=\"\(h)\"") }
            parts.append("traits=\(traitNames(node.accessibilityTraits))")
            if node.accessibilityViewIsModal { parts.append("modal") }
            if let a = node.accessibilityCustomActions, !a.isEmpty {
                parts.append("actions=[\(a.map(\.name).joined(separator: ", "))]")
            }
            lines.append(parts.joined(separator: " "))
        }
        for child in children(of: node) { walk(child, depth: depth + 1, into: &lines) }
    }

    private static func children(of node: NSObject) -> [NSObject] {
        if let elements = node.accessibilityElements as? [NSObject], !elements.isEmpty { return elements }
        let count = node.accessibilityElementCount()
        if count > 0, count != NSNotFound {
            return (0..<count).compactMap { node.accessibilityElement(at: $0) as? NSObject }
        }
        if let view = node as? UIView { return view.subviews }
        return []
    }

    private static func traitNames(_ t: UIAccessibilityTraits) -> String {
        let known: [(UIAccessibilityTraits, String)] = [
            (.button, "button"), (.header, "header"), (.selected, "selected"), (.adjustable, "adjustable"),
            (.image, "image"), (.staticText, "text"), (.notEnabled, "disabled"), (.updatesFrequently, "updates"),
            (.link, "link"), (.tabBar, "tabBar"),
        ]
        let names = known.filter { t.contains($0.0) }.map(\.1)
        return names.isEmpty ? "-" : names.joined(separator: ",")
    }
}
#endif
