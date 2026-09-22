import AppKit

struct MenuShortcut {
    let keyEquivalent: String
    let modifiers: NSEvent.ModifierFlags
}

enum ShortcutMapper {
    private static let numericKeys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    private static let modifierLayers: [NSEvent.ModifierFlags] = [
        [.command],
        [.command, .option],
        [.command, .control],
        [.command, .option, .shift],
        [.command, .control, .shift]
    ]

    static func shortcut(for index: Int) -> MenuShortcut? {
        guard index >= 0 else { return nil }
        let layer = index / numericKeys.count
        let offset = index % numericKeys.count
        guard layer < modifierLayers.count else { return nil }

        return MenuShortcut(
            keyEquivalent: numericKeys[offset],
            modifiers: modifierLayers[layer]
        )
    }
}
