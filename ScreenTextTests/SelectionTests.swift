import AppKit
@testable import ScreenText
import Testing

@Suite(.serialized) @MainActor
struct SelectionTests {
    @Test func `overlay dims and sets crosshair before first mouse press`() async throws {
        let manager = SelectionManager()
        defer { manager.hide() }
        let display = SelectionDisplay(id: 1, frame: .init(x: 0, y: 0, width: 100, height: 100),
                                       visibleFrame: .init(x: 0, y: 0, width: 100, height: 100))
        #expect(manager.prepare(display: display, mode: .box, onEvent: { _ in }))
        try await self.waitForFocus(manager)
        let view = try #require(manager.window?.selectionView)
        #expect(manager.window?.isKeyWindow == true)
        #expect(manager.window?.firstResponder === view)
        #expect(view.selectionRect == nil)
        #expect(NSCursor.current == NSCursor.crosshair)
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let color = try #require(bitmap.colorAt(x: 50, y: 50))
        #expect(abs(color.alphaComponent - 0.28) < 0.02)
    }

    @Test func `repeated sessions receive window mouse events without settings`() async throws {
        let manager = SelectionManager()
        defer { manager.hide() }
        let display = SelectionDisplay(id: 1, frame: .init(x: 0, y: 0, width: 600, height: 400),
                                       visibleFrame: .init(x: 0, y: 0, width: 600, height: 400))
        for _ in 0 ..< 3 {
            var started = false
            var completed: Selection?
            #expect(manager.prepare(display: display, mode: .box, onEvent: { event in
                switch event {
                case .started:
                    started = true
                case let .completed(selection):
                    completed = selection
                default: break
                }
            }))
            try await self.waitForFocus(manager)
            let window = try #require(manager.window)
            #expect(!window.styleMask.contains(.nonactivatingPanel))
            #expect(window.isMainWindow)
            #expect(window.selectionView.needsPanelToBecomeKey)
            #expect(window.isVisible)
            #expect(window.isKeyWindow)
            try window.sendEvent(self.event(.leftMouseDown, at: .init(x: 20, y: 30), window: window))
            try window.sendEvent(self.event(.leftMouseDragged, at: .init(x: 120, y: 90), window: window))
            try window.sendEvent(self.event(.leftMouseUp, at: .init(x: 120, y: 90), window: window))
            #expect(started)
            #expect(completed?.rect == DisplayRect(x: 20, y: 30, width: 100, height: 60))
            #expect(manager.window == nil)
        }
    }

    @Test func `capture owns main window without showing closed settings`() async throws {
        let settings =
            SettingsWindowController(settings: SettingsStore(persistence: SettingsPersistence(defaults: .standard)))
        let settingsWindow = try #require(settings.window)
        // Reproduce a previously opened Settings window remaining AppKit's
        // remembered main window, rather than one that has never been shown.
        settings.show()
        try await Task.sleep(for: .milliseconds(100))
        settingsWindow.close()
        let manager = SelectionManager()
        defer { manager.hide() }
        let display = SelectionDisplay(id: 1, frame: .init(x: 0, y: 0, width: 600, height: 400),
                                       visibleFrame: .init(x: 0, y: 0, width: 600, height: 400))
        for _ in 0 ..< 3 {
            #expect(manager.prepare(display: display, mode: .box, onEvent: { _ in }))
            try await self.waitForFocus(manager)
            #expect(!settingsWindow.isVisible)
            #expect(NSApp.mainWindow === manager.window)
            manager.hide()
            #expect(!settingsWindow.isVisible)
        }
    }

    @Test func `stationary cursor survives resets respects toolbar and stops after hide`() async throws {
        let manager = SelectionManager()
        defer { manager.hide() }
        let display = SelectionDisplay(id: 1, frame: .init(x: 0, y: 0, width: 600, height: 400),
                                       visibleFrame: .init(x: 0, y: 0, width: 600, height: 400))
        #expect(manager.prepare(display: display, mode: .box, onEvent: { _ in }))
        try await self.waitForFocus(manager)
        NSCursor.arrow.set()
        try await Task.sleep(for: .milliseconds(50))
        #expect(NSCursor.current == .crosshair)
        let point = NSEvent.mouseLocation
        manager.setCursorExclusionRect(ScreenRect(appKitGlobalRect: CGRect(
            x: point.x - 10,
            y: point.y - 10,
            width: 20,
            height: 20,
        )))
        NSCursor.crosshair.set()
        try await Task.sleep(for: .milliseconds(50))
        #expect(NSCursor.current == .arrow)
        manager.setCursorExclusionRect(nil)
        #expect(NSCursor.current == .crosshair)
        manager.hide()
        NSCursor.arrow.set()
        try await Task.sleep(for: .milliseconds(50))
        #expect(NSCursor.current == .arrow)
    }

    @Test func `invalid replacement preserves active selection and mode updates`() throws {
        let manager = SelectionManager()
        defer { manager.hide() }
        let display = SelectionDisplay(id: 1, frame: .init(x: 0, y: 0, width: 600, height: 400),
                                       visibleFrame: .init(x: 0, y: 0, width: 600, height: 400))
        #expect(manager.prepare(display: display, mode: .box, onEvent: { _ in }))
        let window = try #require(manager.window)
        manager.setMode(.freehand)
        #expect(window.mode == .freehand)

        let invalid = SelectionDisplay(id: 2, frame: .zero, visibleFrame: .zero)
        #expect(!manager.prepare(display: invalid, mode: .box, onEvent: { _ in }))
        #expect(manager.window === window)
        #expect(window.isVisible)
        #expect(window.mode == .freehand)
    }

    @Test func `normalizes all drag directions`() {
        let pairs: [(DisplayPoint, DisplayPoint)] = [
            (.init(x: 20, y: 30), .init(x: 120, y: 90)),
            (.init(x: 120, y: 90), .init(x: 20, y: 30)),
            (.init(x: 120, y: 30), .init(x: 20, y: 90)),
            (.init(x: 20, y: 90), .init(x: 120, y: 30)),
        ]
        for (start, end) in pairs {
            #expect(Selection.normalizedRect(from: start, to: end) == DisplayRect(x: 20, y: 30, width: 100, height: 60))
        }
    }

    @Test func `rejects clicks and tiny selections`() {
        #expect(!Selection.isValid(.zero))
        #expect(!Selection.isValid(.init(x: 0, y: 0, width: 3.99, height: 100)))
        #expect(!Selection.isValid(.init(x: 0, y: 0, width: 100, height: 3.99)))
        #expect(Selection.isValid(.init(x: 0, y: 0, width: 4, height: 4)))
    }

    @Test func `real mouse handlers clamp to display and clear after release`() throws {
        let window = SelectionWindow(displayFrame: .init(x: -1440, y: 900, width: 600, height: 400))
        let view = window.selectionView
        var started = false
        var completed: DisplayRect?
        view.onEvent = { event in
            switch event {
            case .started: started = true
            case let .completed(geometry): completed = geometry.rect
            case .cancelled: Issue.record("Valid drag was cancelled")
            }
        }
        try view.mouseDown(with: self.event(.leftMouseDown, at: .init(x: 500, y: 350), window: window))
        #expect(started)
        try view.mouseDragged(with: self.event(.leftMouseDragged, at: .init(x: -100, y: -50), window: window))
        #expect(view.selectionRect == DisplayRect(x: 0, y: 0, width: 500, height: 350))
        try view.mouseUp(with: self.event(.leftMouseUp, at: .init(x: -100, y: -50), window: window))
        #expect(completed == DisplayRect(x: 0, y: 0, width: 500, height: 350))
        #expect(view.selectionRect == nil)
    }

    @Test func `manager preserves display local coordinates and hides before callback`() throws {
        let manager = SelectionManager()
        let display = SelectionDisplay(
            id: 42,
            frame: .init(x: -1440, y: 900, width: 600, height: 400),
            visibleFrame: .init(x: -1440, y: 900, width: 600, height: 400),
        )
        var completed: Selection?
        let clipboardChanges = NSPasteboard.general.changeCount
        let prepared = manager.prepare(display: display, mode: .box, onEvent: { event in
            switch event {
            case let .completed(selection):
                #expect(manager.window == nil)
                completed = selection
            case .cancelled:
                Issue.record("Unexpected cancellation")
            default: break
            }
        })
        #expect(prepared)
        let window = try #require(manager.window)
        #expect(window.frame == display.frame.appKitGlobalRect)
        #expect(window.selectionView.bounds.origin == .zero)
        try window.selectionView.mouseDown(with: self.event(.leftMouseDown, at: .init(x: 120, y: 90), window: window))
        try window.selectionView.mouseUp(with: self.event(.leftMouseUp, at: .init(x: 20, y: 30), window: window))
        #expect(completed == Selection(
            displayID: 42,
            rect: .init(x: 20, y: 30, width: 100, height: 60),
            shape: .rectangle,
        ))
        #expect(!window.isVisible)
        #expect(NSPasteboard.general.changeCount == clipboardChanges)
    }

    @Test func `escape cancels active drag and tiny selection cancels`() throws {
        let manager = SelectionManager()
        let display = SelectionDisplay(
            id: 1,
            frame: .init(x: 0, y: 0, width: 600, height: 400),
            visibleFrame: .init(x: 0, y: 0, width: 600, height: 400),
        )
        var cancelled = 0
        let prepare = {
            manager.prepare(display: display, mode: .freehand, onEvent: { event in
                switch event {
                case .completed:
                    Issue.record("Unexpected result")
                case .cancelled:
                    cancelled += 1
                default: break
                }
            })
        }
        #expect(prepare())
        var window = try #require(manager.window)
        try window.selectionView.mouseDown(with: self.event(.leftMouseDown, at: .init(x: 20, y: 30), window: window))
        window.selectionView.cancelOperation(nil)
        #expect(cancelled == 1)
        #expect(manager.window == nil)
        #expect(prepare())
        window = try #require(manager.window)
        try window.selectionView.mouseDown(with: self.event(.leftMouseDown, at: .init(x: 20, y: 30), window: window))
        try window.selectionView.mouseUp(with: self.event(.leftMouseUp, at: .init(x: 21, y: 31), window: window))
        #expect(cancelled == 2)
        #expect(manager.window == nil)
    }

    @Test func `drawn selection preserves concave path and automatically closes it`() throws {
        let manager = SelectionManager()
        let display = SelectionDisplay(
            id: 42,
            frame: .init(x: -600, y: 400, width: 600, height: 400),
            visibleFrame: .init(x: -600, y: 400, width: 600, height: 400),
        )
        let path = [DisplayPoint(x: 20, y: 30), .init(x: 120, y: 30), .init(x: 120, y: 90),
                    .init(x: 70, y: 60), .init(x: 20, y: 90)]
        for points in [path, Array(path.reversed())] {
            var completed: Selection?
            let prepared = manager.prepare(display: display, mode: .box, onEvent: { event in
                switch event {
                case let .completed(selection):
                    #expect(manager.window == nil)
                    completed = selection
                case .cancelled:
                    Issue.record("Unexpected cancellation")
                default: break
                }
            })
            #expect(prepared)
            manager.setMode(.freehand)
            let window = try #require(manager.window)
            try window.selectionView.mouseDown(with: self.event(
                .leftMouseDown,
                at: points[0].displayLocalPoint,
                window: window,
            ))
            for point in points.dropFirst() {
                try window.selectionView.mouseDragged(with: self.event(
                    .leftMouseDragged,
                    at: point.displayLocalPoint,
                    window: window,
                ))
            }
            try window.selectionView.mouseUp(with: self.event(
                .leftMouseUp,
                at: #require(points.last).displayLocalPoint,
                window: window,
            ))
            #expect(completed == Selection(
                displayID: 42,
                rect: .init(x: 20, y: 30, width: 100, height: 60),
                shape: .freehand(points: points),
            ))
            #expect(!window.isVisible)
        }
    }

    private func waitForFocus(_ manager: SelectionManager) async throws {
        for _ in 0 ..< 100 {
            if manager.window?.isKeyWindow == true, manager.window?.isMainWindow == true,
               NSCursor.current == .crosshair
            {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(manager.window?.isKeyWindow == true)
        try #require(manager.window?.isMainWindow == true)
        try #require(NSCursor.current == .crosshair)
    }

    private func event(_ type: NSEvent.EventType, at point: CGPoint, window: NSWindow) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                                        pressure: 1))
    }
}
