import AppKit

@MainActor
final class SettingsWindow: NSWindow {
    init(settingsManager: SettingsManager = .shared, onSave: (() -> Void)? = nil) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable],
                   backing: .buffered,
                   defer: false)
        title = "WakeFox Settings"
        center()
        minSize = NSSize(width: 480, height: 340)

        let vc = InterfaceTableViewController(settingsManager: settingsManager)
        vc.interfaces = settingsManager.getInterfaces()
        vc.onSave = onSave
        contentViewController = vc
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let chars = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        switch chars {
        case "x":
            return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self)
        case "c":
            return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
        case "v":
            return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
        case "a":
            return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}
