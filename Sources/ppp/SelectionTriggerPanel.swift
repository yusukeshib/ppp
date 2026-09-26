import AppKit

@MainActor
final class SelectionTriggerPanel: NSPanel {
    var onReview: (() -> Void)?
    var onPromptSelection: ((UUID) -> Void)?

    private let runButton = FirstMouseButton()
    private let menuButton = FirstMouseButton()
    private let nameLabel = ClickThroughLabel(labelWithString: "")
    private let promptMenu = NSMenu()
    private var profiles: [PromptProfile] = []
    private var selectedPromptID: UUID?
    private var anchorRect: CGRect?
    private var reservedPlacementHeight: CGFloat?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 130, height: 36),
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
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        contentView = effect

        runButton.title = ""
        runButton.bezelStyle = .toolbar
        runButton.showsBorderOnlyWhileMouseInside = true
        runButton.target = self
        runButton.action = #selector(runSelectedPrompt)
        runButton.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        nameLabel.alignment = .left
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setAccessibilityElement(false)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        menuButton.bezelStyle = .toolbar
        menuButton.showsBorderOnlyWhileMouseInside = true
        menuButton.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: L10n.string("Prompts"))?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .medium))
        menuButton.imagePosition = .imageOnly
        menuButton.contentTintColor = .secondaryLabelColor
        menuButton.setAccessibilityLabel(L10n.string("Prompts"))
        menuButton.toolTip = L10n.string("Prompts")
        menuButton.target = self
        menuButton.action = #selector(openPromptMenu)

        menuButton.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(runButton)
        effect.addSubview(nameLabel)
        effect.addSubview(menuButton)

        NSLayoutConstraint.activate([
            runButton.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            runButton.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            runButton.topAnchor.constraint(equalTo: effect.topAnchor),
            runButton.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 10),
            nameLabel.trailingAnchor.constraint(equalTo: menuButton.leadingAnchor, constant: -4),
            nameLabel.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            menuButton.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -3),
            menuButton.topAnchor.constraint(equalTo: effect.topAnchor, constant: 3),
            menuButton.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -3),
            menuButton.widthAnchor.constraint(equalToConstant: 26)
        ])
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func show(
        near accessibilityRect: CGRect?,
        profiles: [PromptProfile],
        selectedPromptID: UUID,
        reservedPlacementHeight: CGFloat? = nil
    ) {
        self.profiles = profiles
        self.selectedPromptID = profiles.first(where: { $0.id == selectedPromptID })?.id
            ?? profiles.first?.id
        anchorRect = accessibilityRect
        self.reservedPlacementHeight = reservedPlacementHeight
        rebuildPromptMenu()
        updateButtons()
        updatePlacement()
        orderFrontRegardless()
    }

    @objc private func runSelectedPrompt() {
        guard selectedPromptID != nil else { return }
        onReview?()
    }

    @objc private func openPromptMenu() {
        guard !promptMenu.items.isEmpty else { return }
        promptMenu.popUp(positioning: nil, at: .zero, in: menuButton)
    }

    @objc private func selectPrompt(_ item: NSMenuItem) {
        guard let id = item.representedObject as? UUID,
              profiles.contains(where: { $0.id == id }) else { return }
        selectedPromptID = id
        for menuItem in promptMenu.items {
            menuItem.state = (menuItem.representedObject as? UUID == id) ? .on : .off
        }
        updateButtons()
        updatePlacement()
        onPromptSelection?(id)
    }

    private func rebuildPromptMenu() {
        promptMenu.removeAllItems()
        for profile in profiles {
            let item = NSMenuItem(title: profile.name, action: #selector(selectPrompt(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile.id
            item.state = profile.id == selectedPromptID ? .on : .off
            promptMenu.addItem(item)
        }
    }

    private func updateButtons() {
        let name = profiles.first(where: { $0.id == selectedPromptID })?.name ?? ""
        nameLabel.stringValue = name
        runButton.isEnabled = selectedPromptID != nil
        menuButton.isEnabled = !profiles.isEmpty
        let description = L10n.format("Run %@", name)
        runButton.setAccessibilityLabel(description)
        runButton.toolTip = description
    }

    private func updatePlacement() {
        let name = profiles.first(where: { $0.id == selectedPromptID })?.name ?? ""
        let font = nameLabel.font ?? NSFont.systemFont(ofSize: 12)
        let nameWidth = (name as NSString).size(withAttributes: [.font: font]).width
        let runWidth = min(max(ceil(nameWidth) + 18, 60), 200)
        let panelSize = NSSize(width: runWidth + 26 + 14, height: 36)
        setContentSize(panelSize)
        setFrameOrigin(
            PanelPositioning.origin(
                for: panelSize,
                near: anchorRect,
                gap: 8,
                reservedHeight: reservedPlacementHeight
            )
        )
    }
}

private final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class ClickThroughLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
