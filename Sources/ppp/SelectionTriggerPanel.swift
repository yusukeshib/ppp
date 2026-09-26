import AppKit

@MainActor
final class SelectionTriggerPanel: NSPanel {
    var onReview: (() -> Void)?
    var onPromptSelection: ((UUID) -> Void)?

    private let actionControl = FirstMouseSegmentedControl()
    private let promptMenu = NSMenu()
    private var profiles: [PromptProfile] = []
    private var selectedPromptID: UUID?
    private var anchorRect: CGRect?
    private var reservedPlacementHeight: CGFloat?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 34),
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

        actionControl.segmentCount = 2
        actionControl.trackingMode = .momentary
        actionControl.segmentDistribution = .fit
        actionControl.controlSize = .small
        actionControl.setImage(
            NSImage(systemSymbolName: "chevron.down", accessibilityDescription: L10n.string("Prompts")),
            forSegment: 1
        )
        actionControl.setWidth(28, forSegment: 1)
        actionControl.setToolTip(L10n.string("Prompts"), forSegment: 1)
        actionControl.target = self
        actionControl.action = #selector(segmentClicked(_:))
        actionControl.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(actionControl)

        NSLayoutConstraint.activate([
            actionControl.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 6),
            actionControl.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -6),
            actionControl.topAnchor.constraint(equalTo: effect.topAnchor, constant: 5),
            actionControl.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -5)
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
        updateControl()
        updatePlacement()
        orderFrontRegardless()
    }

    @objc private func segmentClicked(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0 where selectedPromptID != nil:
            onReview?()
        case 1 where !promptMenu.items.isEmpty:
            promptMenu.popUp(
                positioning: nil,
                at: NSPoint(x: sender.bounds.maxX - sender.widthForSegment(1), y: 0),
                in: sender
            )
        default:
            break
        }
    }

    @objc private func selectPrompt(_ item: NSMenuItem) {
        guard let id = item.representedObject as? UUID,
              profiles.contains(where: { $0.id == id }) else { return }
        selectedPromptID = id
        for menuItem in promptMenu.items {
            menuItem.state = (menuItem.representedObject as? UUID == id) ? .on : .off
        }
        updateControl()
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

    private func updateControl() {
        let name = profiles.first(where: { $0.id == selectedPromptID })?.name ?? ""
        actionControl.setLabel(name, forSegment: 0)
        actionControl.setToolTip(L10n.format("Run %@", name), forSegment: 0)
        actionControl.setEnabled(selectedPromptID != nil, forSegment: 0)
        actionControl.setEnabled(!profiles.isEmpty, forSegment: 1)
    }

    private func updatePlacement() {
        let name = profiles.first(where: { $0.id == selectedPromptID })?.name ?? ""
        let font = actionControl.font ?? NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let nameWidth = (name as NSString).size(withAttributes: [.font: font]).width
        let promptWidth = min(max(ceil(nameWidth) + 24, 64), 200)
        actionControl.setWidth(promptWidth, forSegment: 0)
        let panelSize = NSSize(width: promptWidth + 28 + 12, height: actionControl.fittingSize.height + 10)
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

private final class FirstMouseSegmentedControl: NSSegmentedControl {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
