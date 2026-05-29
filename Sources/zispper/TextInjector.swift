import Cocoa

struct TextInjectionResult {
    let succeeded: Bool
    let reason: String?
}

final class TextInjector {
    static let shared = TextInjector()

    func inject(_ text: String, completion: ((TextInjectionResult) -> Void)? = nil) {
        guard !text.isEmpty else {
            completion?(TextInjectionResult(succeeded: true, reason: nil))
            return
        }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            snapshot.restore(to: pasteboard)
            completion?(TextInjectionResult(succeeded: false, reason: "Failed to write text to the pasteboard"))
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Configuration.textInjectionPasteDelay) {
            guard self.postPasteShortcut() else {
                snapshot.restore(to: pasteboard)
                completion?(TextInjectionResult(succeeded: false, reason: "Failed to synthesize paste keyboard events"))
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + Configuration.textInjectionRestoreDelay) {
                snapshot.restore(to: pasteboard)
                completion?(TextInjectionResult(succeeded: true, reason: nil))
            }
        }
    }

    private func postPasteShortcut() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else {
            return false
        }

        commandDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand

        commandDown.post(tap: .cghidEventTap)
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)
        commandUp.post(tap: .cghidEventTap)
        return true
    }
}

private struct PasteboardSnapshot {
    private struct ItemSnapshot {
        let typeData: [(NSPasteboard.PasteboardType, Data)]
    }

    private let items: [ItemSnapshot]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let itemSnapshots = (pasteboard.pasteboardItems ?? []).map { item in
            let typeData = item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                guard let data = item.data(forType: type) else {
                    return nil
                }
                return (type, data)
            }
            return ItemSnapshot(typeData: typeData)
        }

        return PasteboardSnapshot(items: itemSnapshots)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()

        guard !items.isEmpty else {
            return
        }

        let restoredItems = items.map { snapshot -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in snapshot.typeData {
                item.setData(data, forType: type)
            }
            return item
        }

        pasteboard.writeObjects(restoredItems)
    }
}
