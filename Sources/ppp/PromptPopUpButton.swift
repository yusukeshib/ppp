import AppKit

final class PromptPopUpButton: NSPopUpButton {
    init() {
        super.init(frame: .zero, pullsDown: false)
        controlSize = .mini
        font = .systemFont(ofSize: 11, weight: .semibold)
        isBordered = false
        contentTintColor = .secondaryLabelColor
        cell?.lineBreakMode = .byTruncatingTail
        setAccessibilityLabel(L10n.string("Prompts"))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func setProfiles(_ profiles: [PromptProfile], selectedPromptID: UUID) {
        removeAllItems()
        for profile in profiles {
            let item = NSMenuItem(title: profile.name, action: nil, keyEquivalent: "")
            item.representedObject = profile.id.uuidString
            menu?.addItem(item)
        }
        if let selectedIndex = profiles.firstIndex(where: { $0.id == selectedPromptID }) {
            selectItem(at: selectedIndex)
        }
    }

    var selectedPromptID: UUID? {
        guard let value = selectedItem?.representedObject as? String else { return nil }
        return UUID(uuidString: value)
    }
}
