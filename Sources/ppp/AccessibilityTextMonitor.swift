import AppKit
import ApplicationServices

@MainActor
final class AccessibilityTextMonitor {
    var onCapture: ((CapturedText) -> Void)?
    var onSelectionCleared: (() -> Void)?
    var onUnavailable: (() -> Void)?

    private var observer: AXObserver?
    private var observedApplication: AXUIElement?
    private var observedElement: AXUIElement?
    private var workspaceObserver: NSObjectProtocol?
    private var globalEventMonitor: Any?
    private var pendingCapture: DispatchWorkItem?
    private var pendingActivationRefresh: DispatchWorkItem?
    private var pointerDownLocation: NSPoint?
    private var pendingPointerAnchor: CGRect?
    private var observedPID: pid_t?

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func start() {
        guard workspaceObserver == nil else { return }

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.attachToFrontmostApplication()
                self?.scheduleActivationRefresh()
            }
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyUp, .leftMouseDown, .leftMouseUp, .rightMouseUp]
        ) { [weak self] event in
            let pointerLocation = NSEvent.mouseLocation
            Task { @MainActor in
                guard let self else { return }

                if event.type == .leftMouseDown {
                    self.pointerDownLocation = pointerLocation
                    self.pendingPointerAnchor = nil
                    return
                }

                if event.type == .leftMouseUp {
                    if let pointerDownLocation = self.pointerDownLocation,
                       abs(pointerLocation.x - pointerDownLocation.x) >= 3 ||
                       abs(pointerLocation.y - pointerDownLocation.y) >= 3 {
                        self.pendingPointerAnchor = PanelPositioning.accessibilityRect(
                            atAppKitPoint: pointerLocation
                        )
                    } else {
                        self.pendingPointerAnchor = nil
                    }
                } else {
                    self.pendingPointerAnchor = nil
                }
                self.pointerDownLocation = nil
                self.scheduleCapture()
            }
        }

        attachToFrontmostApplication()
    }

    func refresh() {
        attachToFrontmostApplication()
    }

    func stop() {
        pendingCapture?.cancel()
        pendingCapture = nil
        pendingActivationRefresh?.cancel()
        pendingActivationRefresh = nil
        pointerDownLocation = nil
        pendingPointerAnchor = nil

        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
        detachAXObserver()
    }

    private func attachToFrontmostApplication() {
        guard Self.isTrusted,
              let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            detachAXObserver()
            onUnavailable?()
            return
        }

        let pid = application.processIdentifier
        if observedPID == pid {
            attachToFocusedElement()
            scheduleCapture()
            return
        }

        if observedPID != nil {
            onUnavailable?()
        }
        detachAXObserver()

        var newObserver: AXObserver?
        let error = AXObserverCreate(pid, Self.observerCallback, &newObserver)
        guard error == .success, let newObserver else { return }

        let appElement = AXUIElementCreateApplication(pid)
        let context = Unmanaged.passUnretained(self).toOpaque()
        observer = newObserver
        observedApplication = appElement
        observedPID = pid

        AXObserverAddNotification(
            newObserver,
            appElement,
            kAXFocusedUIElementChangedNotification as CFString,
            context
        )
        AXObserverAddNotification(
            newObserver,
            appElement,
            kAXFocusedWindowChangedNotification as CFString,
            context
        )
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(newObserver),
            .commonModes
        )

        attachToFocusedElement()
        scheduleCapture()
    }

    private func attachToFocusedElement() {
        guard let observer else { return }

        if let observedElement {
            AXObserverRemoveNotification(
                observer,
                observedElement,
                kAXValueChangedNotification as CFString
            )
            AXObserverRemoveNotification(
                observer,
                observedElement,
                kAXSelectedTextChangedNotification as CFString
            )
        }

        guard let focused = focusedElement() else {
            observedElement = nil
            onUnavailable?()
            return
        }
        let focusChanged = observedElement.map { !CFEqual($0, focused) } ?? false
        observedElement = focused
        if focusChanged {
            onUnavailable?()
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(
            observer,
            focused,
            kAXValueChangedNotification as CFString,
            context
        )
        AXObserverAddNotification(
            observer,
            focused,
            kAXSelectedTextChangedNotification as CFString,
            context
        )
    }

    private func detachAXObserver() {
        if let observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
        observer = nil
        observedApplication = nil
        observedElement = nil
        observedPID = nil
    }

    private func handleNotification(_ notification: CFString) {
        if notification as String == kAXFocusedUIElementChangedNotification as String ||
            notification as String == kAXFocusedWindowChangedNotification as String {
            attachToFocusedElement()
        }
        scheduleCapture()
    }

    private func scheduleActivationRefresh() {
        pendingActivationRefresh?.cancel()
        guard let expectedPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              expectedPID != ProcessInfo.processInfo.processIdentifier
        else {
            pendingActivationRefresh = nil
            return
        }

        // Native text views can restore their first responder and AX selection
        // after the application-activation notification has already fired.
        let work = DispatchWorkItem { [weak self] in
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedPID else {
                return
            }
            self?.attachToFrontmostApplication()
        }
        pendingActivationRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func scheduleCapture() {
        pendingCapture?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.captureNow()
        }
        pendingCapture = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: work)
    }

    private func captureNow() {
        // Selection-change notifications can arrive repeatedly during a drag.
        // Wait for mouse-up so the trigger follows the completed selection.
        guard (NSEvent.pressedMouseButtons & 1) == 0 else { return }

        let pointerAnchor = pendingPointerAnchor
        pendingPointerAnchor = nil

        guard Self.isTrusted,
              let element = focusedElement(),
              !isSecure(element)
        else {
            onUnavailable?()
            return
        }

        guard let text = selectedString(of: element),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            onSelectionCleared?()
            return
        }

        pendingActivationRefresh?.cancel()
        pendingActivationRefresh = nil

        let application = observedPID.flatMap { NSRunningApplication(processIdentifier: $0) }
        let appName = application?.localizedName
        onCapture?(
            CapturedText(
                text: text,
                caretBounds: pointerAnchor
                    ?? caretBounds(of: element)
                    ?? elementBounds(of: element),
                applicationName: appName
            )
        )
    }

    private func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        guard let value = attribute(kAXFocusedUIElementAttribute as CFString, of: systemWide),
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        let element = value as! AXUIElement
        return element
    }

    private func selectedString(of element: AXUIElement) -> String? {
        if let selected = attribute(kAXSelectedTextAttribute as CFString, of: element) as? String,
           !selected.isEmpty {
            return selected
        }
        if let selected = textMarkerSelectedString(of: element), !selected.isEmpty {
            return selected
        }

        guard let text = stringValue(of: element),
              let range = selectedTextRange(of: element),
              range.location >= 0,
              range.length > 0
        else { return nil }

        let textLength = (text as NSString).length
        guard range.location <= textLength,
              range.length <= textLength - range.location
        else { return nil }
        return (text as NSString).substring(
            with: NSRange(location: range.location, length: range.length)
        )
    }

    private func textMarkerSelectedString(of element: AXUIElement) -> String? {
        var candidate: AXUIElement? = element
        for _ in 0..<5 {
            guard let current = candidate else { break }
            if let markerRange = attribute("AXSelectedTextMarkerRange" as CFString, of: current) {
                var result: CFTypeRef?
                let error = AXUIElementCopyParameterizedAttributeValue(
                    current,
                    "AXStringForTextMarkerRange" as CFString,
                    markerRange,
                    &result
                )
                if error == .success, let string = result as? String, !string.isEmpty {
                    return string
                }
            }
            candidate = parent(of: current)
        }
        return nil
    }

    private func stringValue(of element: AXUIElement) -> String? {
        let value = attribute(kAXValueAttribute as CFString, of: element)
        if let string = value as? String { return string }
        if let attributed = value as? NSAttributedString { return attributed.string }
        return nil
    }

    private func selectedTextRange(of element: AXUIElement) -> CFRange? {
        guard let value = attribute(kAXSelectedTextRangeAttribute as CFString, of: element),
              CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }

        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    private func isSecure(_ element: AXUIElement) -> Bool {
        let subrole = attribute(kAXSubroleAttribute as CFString, of: element) as? String
        if subrole == kAXSecureTextFieldSubrole as String { return true }

        let role = attribute(kAXRoleAttribute as CFString, of: element) as? String
        return role == "AXSecureTextField"
    }

    private func caretBounds(of element: AXUIElement) -> CGRect? {
        characterRangeCaretBounds(of: element) ?? textMarkerCaretBounds(of: element)
    }

    /// WebKit, Chromium, and Electron commonly expose selection geometry through
    /// text markers rather than the standard CFRange accessibility attributes.
    private func textMarkerCaretBounds(of element: AXUIElement) -> CGRect? {
        var candidate: AXUIElement? = element

        // Some web controls publish markers on a nearby ancestor instead of the
        // focused element, so walk a small bounded portion of the AX tree.
        for _ in 0..<5 {
            guard let current = candidate else { break }
            if let value = attribute("AXSelectedTextMarkerRange" as CFString, of: current),
               CFGetTypeID(value) == AXTextMarkerRangeGetTypeID() {
                let selectedRange = value as! AXTextMarkerRange
                let endMarker = AXTextMarkerRangeCopyEndMarker(selectedRange)

                if let previousValue = parameterizedValue(
                    attribute: "AXPreviousTextMarkerForTextMarker" as CFString,
                    parameter: endMarker,
                    of: current
                ), CFGetTypeID(previousValue) == AXTextMarkerGetTypeID() {
                    let previousMarker = previousValue as! AXTextMarker
                    let endpointRange = AXTextMarkerRangeCreate(
                        nil,
                        previousMarker,
                        endMarker
                    )
                    if let rect = parameterizedRect(
                        attribute: "AXBoundsForTextMarkerRange" as CFString,
                        parameter: endpointRange,
                        of: current
                    ) {
                        return rect
                    }
                }

                // Some AX providers can resolve a collapsed marker range even
                // when they do not expose the previous-marker operation.
                let collapsedRange = AXTextMarkerRangeCreate(nil, endMarker, endMarker)
                if let rect = parameterizedRect(
                    attribute: "AXBoundsForTextMarkerRange" as CFString,
                    parameter: collapsedRange,
                    of: current
                ) {
                    return rect
                }
            }
            candidate = parent(of: current)
        }
        return nil
    }

    private func characterRangeCaretBounds(of element: AXUIElement) -> CGRect? {
        guard var selectedRange = selectedTextRange(of: element),
              selectedRange.location >= 0,
              selectedRange.length > 0
        else { return nil }
        let (caretLocation, overflow) = selectedRange.location.addingReportingOverflow(
            selectedRange.length - 1
        )
        guard !overflow else { return nil }
        selectedRange.location = caretLocation
        selectedRange.length = 1
        guard let parameter = AXValueCreate(.cfRange, &selectedRange) else { return nil }
        return parameterizedRect(
            attribute: kAXBoundsForRangeParameterizedAttribute as CFString,
            parameter: parameter,
            of: element
        )
    }

    private func parameterizedRect(
        attribute name: CFString,
        parameter: CFTypeRef,
        of element: AXUIElement
    ) -> CGRect? {
        guard let result = parameterizedValue(
            attribute: name,
            parameter: parameter,
            of: element
        ), CFGetTypeID(result) == AXValueGetTypeID()
        else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(result as! AXValue, .cgRect, &rect),
              !rect.isNull,
              rect.height > 0
        else { return nil }
        return rect
    }

    private func parameterizedValue(
        attribute name: CFString,
        parameter: CFTypeRef,
        of element: AXUIElement
    ) -> CFTypeRef? {
        var result: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(
            element,
            name,
            parameter,
            &result
        )
        guard error == .success else { return nil }
        return result
    }

    private func parent(of element: AXUIElement) -> AXUIElement? {
        guard let value = attribute(kAXParentAttribute as CFString, of: element),
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        let parent = value as! AXUIElement
        return parent
    }

    private func elementBounds(of element: AXUIElement) -> CGRect? {
        guard let positionValue = attribute(kAXPositionAttribute as CFString, of: element),
              let sizeValue = attribute(kAXSizeAttribute as CFString, of: element),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }

        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: point, size: size)
    }

    private func attribute(_ name: CFString, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
        return value
    }

    private static let observerCallback: AXObserverCallback = { _, _, notification, context in
        guard let context else { return }
        let monitor = Unmanaged<AccessibilityTextMonitor>.fromOpaque(context).takeUnretainedValue()
        Task { @MainActor in
            monitor.handleNotification(notification)
        }
    }
}
