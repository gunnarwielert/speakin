import AppKit
import Carbon

@MainActor
struct TextInserter {
    static func insertText(_ text: String) -> Bool {
        guard !text.isEmpty else { return true }

        let source = CGEventSource(stateID: .hidSystemState)

        for char in text {
            var chars = Array(String(char).utf16)

            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else {
                continue
            }
            keyDown.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
            keyDown.post(tap: .cgAnnotatedSessionEventTap)

            guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                continue
            }
            keyUp.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
            keyUp.post(tap: .cgAnnotatedSessionEventTap)
        }

        return true
    }

    static func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static func insertTextWithFallback(_ text: String) -> Bool {
        guard !text.isEmpty else { return true }

        let focusedElement = getFocusedTextElement()

        if focusedElement {
            return insertText(text)
        } else {
            copyToClipboard(text)
            return false
        }
    }

    private static func getFocusedTextElement() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        guard result == .success, let element = focusedElement else {
            return false
        }

        var role: AnyObject?
        AXUIElementCopyAttributeValue(element as! AXUIElement, kAXRoleAttribute as CFString, &role)

        if let roleString = role as? String {
            let textRoles = [
                kAXTextFieldRole as String,
                kAXTextAreaRole as String,
                kAXComboBoxRole as String,
                "AXSearchField"
            ]

            if textRoles.contains(roleString) {
                return true
            }
        }

        var isEditable: AnyObject?
        let editableResult = AXUIElementCopyAttributeValue(element as! AXUIElement, "AXEditable" as CFString, &isEditable)

        if editableResult == .success, let editable = isEditable as? Bool, editable {
            return true
        }

        var value: AnyObject?
        let valueResult = AXUIElementCopyAttributeValue(element as! AXUIElement, kAXValueAttribute as CFString, &value)

        if valueResult == .success && value is String {
            return true
        }

        return false
    }
}
