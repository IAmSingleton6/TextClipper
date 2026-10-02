import AppKit
@testable import ScreenText
import Testing

extension DesktopTests {
    @MainActor
    struct SelectionTests {
        @Test func `overlay dims the display and claims focus before the first press`() async throws {
            let selection = SelectionFixture(display: SelectionDisplay(
                id: 1, frame: .init(x: 0, y: 0, width: 100, height: 100),
                visibleFrame: .init(x: 0, y: 0, width: 100, height: 100),
            ))

            // WHEN
            try selection.start()
            try await selection.waitUntilFocused()

            // THEN
            let window = try selection.window
            let view = try selection.view
            #expect(window.isKeyWindow)
            #expect(window.firstResponder === view)
            #expect(view.selectionRect == nil)
            #expect(NSCursor.current == .crosshair)
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            #expect(try abs(#require(bitmap.colorAt(x: 50, y: 50)).alphaComponent - 0.28) < 0.02)
        }

        @Test func `repeated sessions receive actual window mouse events`() async throws {
            let selection = SelectionFixture(dispatchThroughWindow: true)
            for session in 1 ... 3 {
                // GIVEN
                try selection.start()
                try await selection.waitUntilFocused()
                let window = try selection.window
                #expect(!window.styleMask.contains(.nonactivatingPanel))
                #expect(window.isMainWindow)
                #expect(window.selectionView.needsPanelToBecomeKey)
                #expect(window.isVisible)
                #expect(window.isKeyWindow)

                // WHEN
                try selection.press(at: .init(x: 20, y: 30))
                try selection.drag(to: .init(x: 120, y: 90))
                try selection.release(at: .init(x: 120, y: 90))

                // THEN
                #expect(selection.starts == session)
                #expect(selection.completed.count == session)
                #expect(selection.cancellations == 0)
                #expect(selection.completed.last?.rect == DisplayRect(x: 20, y: 30, width: 100, height: 60))
                #expect(selection.manager.window == nil)
            }
        }

        @Test func `capture owns the main window without reopening previously closed settings`() async throws {
            let storage = try SettingsFixture()
            let settings = SettingsWindowController(settings: storage.settings)
            let settingsWindow = try #require(settings.window)
            defer { settingsWindow.close() }
            let selection = SelectionFixture()

            // GIVEN
            settings.show()
            try await NativeWindow.waitUntilFocused(settingsWindow)
            settingsWindow.close()

            for _ in 0 ..< 3 {
                // WHEN
                try selection.start()
                try await selection.waitUntilFocused()

                // THEN
                #expect(!settingsWindow.isVisible)
                #expect(NSApp.mainWindow === selection.manager.window)
                selection.hide()
                #expect(!settingsWindow.isVisible)
            }
        }

        @Test func `cursor maintenance restores the crosshair after a stationary reset`() async throws {
            let selection = SelectionFixture()

            // GIVEN
            try selection.start()
            try await selection.waitUntilFocused()

            // WHEN
            NSCursor.arrow.set()
            // Native integration: the private AppKit timer has no controllable tick API.
            try await Task.sleep(for: .milliseconds(50))

            // THEN
            #expect(NSCursor.current == .crosshair)
        }

        @Test func `cursor maintenance keeps the arrow over the toolbar exclusion`() async throws {
            let selection = SelectionFixture()

            // GIVEN
            try selection.start()
            try await selection.waitUntilFocused()
            selection.manager.setCursorExclusionRect(self.rectAroundPointer())
            NSCursor.crosshair.set()

            // WHEN
            // Native integration: observe the real cursor-maintenance timer.
            try await Task.sleep(for: .milliseconds(50))

            // THEN
            #expect(NSCursor.current == .arrow)
        }

        @Test func `removing the toolbar exclusion immediately restores the crosshair`() async throws {
            let selection = SelectionFixture()

            // GIVEN
            try selection.start()
            try await selection.waitUntilFocused()
            selection.manager.setCursorExclusionRect(self.rectAroundPointer())
            #expect(NSCursor.current == .arrow)

            // WHEN
            selection.manager.setCursorExclusionRect(nil)

            // THEN
            #expect(NSCursor.current == .crosshair)
        }

        @Test func `hiding selection stops stationary cursor maintenance`() async throws {
            let selection = SelectionFixture()

            // GIVEN
            try selection.start()
            try await selection.waitUntilFocused()
            selection.hide()

            // WHEN
            NSCursor.arrow.set()
            // Native integration: a stray real timer tick would reset this cursor.
            try await Task.sleep(for: .milliseconds(50))

            // THEN
            #expect(NSCursor.current == .arrow)
        }

        @Test(arguments: [CaptureMode.box, .freehand])
        func `selecting a mode updates the native selection window`(mode: CaptureMode) throws {
            let selection = SelectionFixture(initialMode: mode == .box ? .freehand : .box)

            // GIVEN
            try selection.start()

            // WHEN
            selection.selectMode(mode)

            // THEN
            #expect(try selection.window.mode == mode)
        }

        @Test func `an invalid replacement preserves the visible selection and its mode`() throws {
            let selection = SelectionFixture(initialMode: .freehand)

            // GIVEN
            try selection.start()
            let window = try selection.window

            // WHEN
            let prepared = selection.manager.prepare(
                display: SelectionDisplay(id: 2, frame: .zero, visibleFrame: .zero), mode: .box, onEvent: { _ in },
            )

            // THEN
            #expect(!prepared)
            #expect(selection.manager.window === window)
            #expect(window.isVisible)
            #expect(window.mode == .freehand)
        }

        @Test(arguments: [
            (DisplayPoint(x: 20, y: 30), DisplayPoint(x: 120, y: 90)),
            (.init(x: 120, y: 90), .init(x: 20, y: 30)),
            (.init(x: 120, y: 30), .init(x: 20, y: 90)),
            (.init(x: 20, y: 90), .init(x: 120, y: 30)),
        ])
        func `every drag direction produces the same normalized box`(drag: (DisplayPoint, DisplayPoint)) {
            #expect(Selection.normalizedRect(from: drag.0, to: drag.1) == DisplayRect(
                x: 20,
                y: 30,
                width: 100,
                height: 60,
            ))
        }

        @Test(arguments: [DisplayRect.zero, .init(x: 0, y: 0, width: 3.99, height: 100),
                          .init(x: 0, y: 0, width: 100, height: 3.99), .init(
                              x: .infinity,
                              y: 0,
                              width: 10,
                              height: 10,
                          )])
        func `clicks tiny bounds and nonfinite selections are rejected`(rect: DisplayRect) {
            #expect(!Selection.isValid(rect))
        }

        @Test func `a box at the exact minimum size is accepted`() {
            #expect(Selection.isValid(.init(x: 0, y: 0, width: 4, height: 4)))
        }

        @Test func `native box dragging clamps to the display and clears after release`() throws {
            let selection = SelectionFixture(display: SelectionDisplay(
                id: 42, frame: .init(x: -1440, y: 900, width: 600, height: 400),
                visibleFrame: .init(x: -1440, y: 900, width: 600, height: 400),
            ))

            // GIVEN
            try selection.start()
            let view = try selection.view
            try selection.press(at: .init(x: 500, y: 350))
            #expect(selection.starts == 1)

            // WHEN
            try selection.drag(to: .init(x: -100, y: -50))
            #expect(view.selectionRect == DisplayRect(x: 0, y: 0, width: 500, height: 350))
            try selection.release(at: .init(x: -100, y: -50))

            // THEN
            #expect(selection.completed.first?.rect == DisplayRect(x: 0, y: 0, width: 500, height: 350))
            #expect(selection.cancellations == 0)
            #expect(view.selectionRect == nil)
        }

        @Test func `selection preserves local coordinates and hides before delivering its result`() throws {
            let selection = SelectionFixture(display: SelectionDisplay(
                id: 42, frame: .init(x: -1440, y: 900, width: 600, height: 400),
                visibleFrame: .init(x: -1440, y: 900, width: 600, height: 400),
            ), onEvent: { selection, event in
                if case .completed = event {
                    #expect(selection.manager.window == nil)
                }
            })
            let clipboardChanges = NSPasteboard.general.changeCount

            // GIVEN
            try selection.start()
            let window = try selection.window
            #expect(window.frame == selection.display.frame.appKitGlobalRect)
            #expect(window.selectionView.bounds.origin == .zero)
            try selection.press(at: .init(x: 120, y: 90))

            // WHEN
            try selection.release(at: .init(x: 20, y: 30))

            // THEN
            #expect(selection.completed == [Selection(displayID: 42, rect: .init(x: 20, y: 30, width: 100, height: 60),
                                                      shape: .rectangle)])
            #expect(selection.cancellations == 0)
            #expect(!window.isVisible)
            #expect(NSPasteboard.general.changeCount == clipboardChanges)
        }

        @Test(arguments: [CaptureMode.box, .freehand])
        func `Escape cancels an active drag without completing it`(mode: CaptureMode) throws {
            let selection = SelectionFixture(initialMode: mode)

            // GIVEN
            try selection.start()
            try selection.press(at: .init(x: 20, y: 30))

            // WHEN
            try selection.cancel()

            // THEN
            #expect(selection.cancellations == 1)
            #expect(selection.completed.isEmpty)
            #expect(selection.manager.window == nil)
        }

        @Test(arguments: [CaptureMode.box, .freehand])
        func `releasing a tiny drag cancels without a result`(mode: CaptureMode) throws {
            let selection = SelectionFixture(initialMode: mode)

            // GIVEN
            try selection.start()
            try selection.press(at: .init(x: 20, y: 30))

            // WHEN
            try selection.release(at: .init(x: 21, y: 31))

            // THEN
            #expect(selection.cancellations == 1)
            #expect(selection.completed.isEmpty)
            #expect(selection.manager.window == nil)
        }

        @Test(arguments: [false, true])
        func `drawn selection preserves its concave boundary in either winding direction`(reversed: Bool) throws {
            let path = [DisplayPoint(x: 20, y: 30), .init(x: 120, y: 30), .init(x: 120, y: 90),
                        .init(x: 70, y: 60), .init(x: 20, y: 90)]
            let points = reversed ? Array(path.reversed()) : path
            let selection = SelectionFixture(display: SelectionDisplay(
                id: 42, frame: .init(x: -600, y: 400, width: 600, height: 400),
                visibleFrame: .init(x: -600, y: 400, width: 600, height: 400),
            ), initialMode: .freehand, onEvent: { selection, event in
                if case .completed = event {
                    #expect(selection.manager.window == nil)
                }
            })

            // GIVEN
            try selection.start()
            let window = try selection.window
            try selection.press(at: points[0].displayLocalPoint)
            for point in points.dropFirst() {
                try selection.drag(to: point.displayLocalPoint)
            }

            // WHEN
            try selection.release(at: #require(points.last).displayLocalPoint)

            // THEN
            #expect(selection.completed == [Selection(displayID: 42, rect: .init(x: 20, y: 30, width: 100, height: 60),
                                                      shape: .freehand(points: points))])
            #expect(selection.cancellations == 0)
            #expect(!window.isVisible)
        }

        @Test func `mouse movement and release without a press produce no selection events`() throws {
            let drawing = SelectionViewFixture(mode: .box)
            var events = 0
            drawing.view.onEvent = { _ in events += 1 }

            // WHEN
            try drawing.drag(to: .init(x: 50, y: 50))
            try drawing.release(at: .init(x: 50, y: 50))

            // THEN
            #expect(events == 0)
            #expect(drawing.view.selectionRect == nil)
        }

        private func rectAroundPointer() -> ScreenRect {
            let point = NSEvent.mouseLocation
            return ScreenRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20)
        }
    }
}
