import AppKit
import ApplicationServices

extension NordApp {
    /// Presses the app's own "Disconnect" control, looked up through the Accessibility API:
    /// first in its menu bar extra, then in its Dock menu.
    public static func disconnect() throws {
        guard url != nil else { throw NordAppError.notInstalled }
        guard AXIsProcessTrusted() else {
            throw NordAppError.accessibilityDenied
        }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            throw NordAppError.notRunning
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        for statusItem in AX.children(of: AX.element(axApp, kAXExtrasMenuBarAttribute)) {
            AX.press(statusItem)
            Thread.sleep(forTimeInterval: 0.5)
            // A classic NSMenu hangs off the status item; a SwiftUI panel shows up as a window.
            let surfaces = AX.children(of: statusItem) + AX.elements(axApp, kAXWindowsAttribute)
            if let control = surfaces.lazy.compactMap({ AX.findDisconnect(in: $0) }).first {
                AX.press(control)
                return
            }
            AX.dismiss(statusItem)
        }

        if let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first {
            let axDock = AXUIElementCreateApplication(dock.processIdentifier)
            let tiles = AX.children(of: axDock).flatMap { AX.children(of: $0) }
            if let tile = tiles.first(where: { AX.string($0, kAXTitleAttribute) == "NordVPN" }) {
                AXUIElementPerformAction(tile, kAXShowMenuAction as CFString)
                Thread.sleep(forTimeInterval: 0.5)
                if let control = AX.children(of: tile).lazy.compactMap({ AX.findDisconnect(in: $0) }).first {
                    AX.press(control)
                    return
                }
                AX.dismiss(tile)
            }
        }
        throw NordAppError.disconnectItemNotFound
    }
}

/// Thin helpers over the C Accessibility API.
enum AX {
    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    static func children(of element: AXUIElement?) -> [AXUIElement] {
        element.map { elements($0, kAXChildrenAttribute) } ?? []
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func press(_ element: AXUIElement) {
        AXUIElementPerformAction(element, kAXPressAction as CFString)
    }

    /// Closes whatever `element` opened: its menu if it has one, otherwise by toggling it again.
    static func dismiss(_ element: AXUIElement) {
        if let menu = children(of: element).first(where: { string($0, kAXRoleAttribute) == kAXMenuRole }) {
            AXUIElementPerformAction(menu, kAXCancelAction as CFString)
        } else {
            press(element)
        }
    }

    /// Depth-first search for an enabled menu item or button labelled "Disconnect…".
    static func findDisconnect(in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        let role = string(element, kAXRoleAttribute)
        if role == kAXMenuItemRole || role == kAXButtonRole {
            let labels = [kAXTitleAttribute, kAXDescriptionAttribute].compactMap { string(element, $0) }
            if labels.contains(where: { $0.lowercased().hasPrefix("disconnect") }) { return element }
        }
        guard depth < 12 else { return nil }
        for child in children(of: element) {
            if let found = findDisconnect(in: child, depth: depth + 1) { return found }
        }
        return nil
    }
}
