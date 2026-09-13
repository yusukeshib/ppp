import AppKit

private final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class FirstMousePopUpButton: NSPopUpButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class SelectionTriggerPanel: NSPanel {
    var onReview: (() -> Void)?
    var onPromptSelection: ((UUID) -> Void)?

    private let promptPopUp = FirstMousePopUpButton(frame: .zero, pullsDown: false)
    private let runButton = FirstMouseButton(title: "", target: nil, action: nil)

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 88, height: 34),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 9
        effect.layer?.masksToBounds = true
        contentView = effect

        promptPopUp.target = self
        promptPopUp.action = #selector(promptSelectionChanged)
        promptPopUp.controlSize = .small
        promptPopUp.font = .systemFont(ofSize: 12, weight: .semibold)
        promptPopUp.cell?.lineBreakMode = .byTruncatingTail
        promptPopUp.setAccessibilityLabel(L10n.string("Prompts"))
        promptPopUp.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(promptPopUp)

        runButton.target = self
        runButton.action = #selector(reviewSelection)
        runButton.bezelStyle = .recessed
        runButton.isBordered = false
        runButton.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: nil)
        runButton.contentTintColor = .labelColor
        runButton.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(runButton)

        NSLayoutConstraint.activate([
            promptPopUp.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 6),
            promptPopUp.topAnchor.constraint(equalTo: effect.topAnchor, constant: 4),
            promptPopUp.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -4),
            runButton.leadingAnchor.constraint(equalTo: promptPopUp.trailingAnchor, constant: 2),
            runButton.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -6),
            runButton.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            runButton.widthAnchor.constraint(equalToConstant: 26),
            runButton.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func show(
        near accessibilityRect: CGRect?,
        profiles: [PromptProfile],
        selectedPromptID: UUID
    ) {
        promptPopUp.removeAllItems()
        for profile in profiles {
            let item = NSMenuItem(title: profile.name, action: nil, keyEquivalent: "")
            item.representedObject = profile.id.uuidString
            promptPopUp.menu?.addItem(item)
        }

        if let selectedIndex = profiles.firstIndex(where: { $0.id == selectedPromptID }) {
            promptPopUp.selectItem(at: selectedIndex)
        }

        let promptName = promptPopUp.titleOfSelectedItem ?? ""
        runButton.toolTip = L10n.format("Run %@", promptName)
        runButton.setAccessibilityLabel(runButton.toolTip)
        let width = min(max(promptPopUp.intrinsicContentSize.width + 40, 124), 320)
        let panelSize = NSSize(width: width, height: 34)
        setContentSize(panelSize)
        setFrameOrigin(
            PanelPositioning.origin(for: panelSize, near: accessibilityRect, gap: 6)
        )
        orderFrontRegardless()
    }

    @objc private func promptSelectionChanged() {
        guard let value = promptPopUp.selectedItem?.representedObject as? String,
              let id = UUID(uuidString: value)
        else { return }
        runButton.toolTip = L10n.format("Run %@", promptPopUp.titleOfSelectedItem ?? "")
        runButton.setAccessibilityLabel(runButton.toolTip)
        onPromptSelection?(id)
    }

    @objc private func reviewSelection() {
        onReview?()
    }

}
