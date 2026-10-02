import AppKit
import Testing
@testable import ScreenText

@Suite @MainActor
struct SelectionTests {
    @Test func normalizesAllDragDirections() {
        let pairs: [(CGPoint, CGPoint)] = [
            (.init(x: 20, y: 30), .init(x: 120, y: 90)),
            (.init(x: 120, y: 90), .init(x: 20, y: 30)),
            (.init(x: 120, y: 30), .init(x: 20, y: 90)),
            (.init(x: 20, y: 90), .init(x: 120, y: 30))
        ]
        for (start, end) in pairs {
            #expect(Selection.normalizedRect(from: start, to: end) == CGRect(x: 20, y: 30, width: 100, height: 60))
        }
    }

    @Test func rejectsClicksAndTinySelections() {
        #expect(!Selection.isValid(.zero))
        #expect(!Selection.isValid(.init(x: 0, y: 0, width: 3.99, height: 100)))
        #expect(!Selection.isValid(.init(x: 0, y: 0, width: 100, height: 3.99)))
        #expect(Selection.isValid(.init(x: 0, y: 0, width: 4, height: 4)))
    }

    @Test func realMouseHandlersClampToDisplayAndClearAfterRelease() throws {
        let window = SelectionWindow(displayFrame: .init(x: -1440, y: 900, width: 600, height: 400))
        let view = window.selectionView
        var started = false
        var completed: CGRect?
        view.onStarted = { started = true }
        view.onFinished = { completed = $0?.rect }
        view.mouseDown(with: try event(.leftMouseDown, at: .init(x: 500, y: 350), window: window))
        #expect(started)
        view.mouseDragged(with: try event(.leftMouseDragged, at: .init(x: -100, y: -50), window: window))
        #expect(view.selectionRect == CGRect(x: 0, y: 0, width: 500, height: 350))
        view.mouseUp(with: try event(.leftMouseUp, at: .init(x: -100, y: -50), window: window))
        #expect(completed == CGRect(x: 0, y: 0, width: 500, height: 350))
        #expect(view.selectionRect == nil)
    }

    @Test func managerPreservesDisplayLocalCoordinatesAndHidesBeforeCallback() throws {
        let manager = SelectionManager()
        let display = SelectionDisplay(id: 42, frame: .init(x: -1440, y: 900, width: 600, height: 400), visibleFrame: .init(x: -1440, y: 900, width: 600, height: 400))
        var completed: Selection?
        let clipboardChanges = NSPasteboard.general.changeCount
        let prepared = manager.prepare(display: display, mode: .box, onStarted: {}, onCompleted: {
            #expect(manager.window == nil)
            completed = $0
        }, onCancelled: { Issue.record("Unexpected cancellation") })
        #expect(prepared)
        let window = try #require(manager.window)
        #expect(window.frame == display.frame)
        #expect(window.selectionView.bounds.origin == .zero)
        window.selectionView.mouseDown(with: try event(.leftMouseDown, at: .init(x: 120, y: 90), window: window))
        window.selectionView.mouseUp(with: try event(.leftMouseUp, at: .init(x: 20, y: 30), window: window))
        #expect(completed == Selection(displayID: 42, rect: .init(x: 20, y: 30, width: 100, height: 60), shape: .rectangle))
        #expect(!window.isVisible)
        #expect(NSPasteboard.general.changeCount == clipboardChanges)
    }

    @Test func escapeCancelsActiveDragAndTinySelectionCancels() throws {
        let manager = SelectionManager()
        let display = SelectionDisplay(id: 1, frame: .init(x: 0, y: 0, width: 600, height: 400), visibleFrame: .init(x: 0, y: 0, width: 600, height: 400))
        var cancelled = 0
        let prepare = {
            manager.prepare(display: display, mode: .freehand, onStarted: {}, onCompleted: { _ in Issue.record("Unexpected result") }, onCancelled: { cancelled += 1 })
        }
        #expect(prepare())
        var window = try #require(manager.window)
        window.selectionView.mouseDown(with: try event(.leftMouseDown, at: .init(x: 20, y: 30), window: window))
        window.selectionView.cancelOperation(nil)
        #expect(cancelled == 1)
        #expect(manager.window == nil)
        #expect(prepare())
        window = try #require(manager.window)
        window.selectionView.mouseDown(with: try event(.leftMouseDown, at: .init(x: 20, y: 30), window: window))
        window.selectionView.mouseUp(with: try event(.leftMouseUp, at: .init(x: 21, y: 31), window: window))
        #expect(cancelled == 2)
        #expect(manager.window == nil)
    }

    @Test func drawnSelectionPreservesConcavePathAndAutomaticallyClosesIt() throws {
        let manager = SelectionManager()
        let display = SelectionDisplay(id: 42, frame: .init(x: -600, y: 400, width: 600, height: 400), visibleFrame: .init(x: -600, y: 400, width: 600, height: 400))
        let path = [CGPoint(x: 20, y: 30), CGPoint(x: 120, y: 30), CGPoint(x: 120, y: 90),
                    CGPoint(x: 70, y: 60), CGPoint(x: 20, y: 90)]
        for points in [path, Array(path.reversed())] {
            var completed: Selection?
            let prepared = manager.prepare(display: display, mode: .box, onStarted: {}, onCompleted: {
                #expect(manager.window == nil)
                completed = $0
            }, onCancelled: { Issue.record("Unexpected cancellation") })
            #expect(prepared)
            manager.setMode(.freehand)
            let window = try #require(manager.window)
            window.selectionView.mouseDown(with: try event(.leftMouseDown, at: points[0], window: window))
            for point in points.dropFirst() {
                window.selectionView.mouseDragged(with: try event(.leftMouseDragged, at: point, window: window))
            }
            window.selectionView.mouseUp(with: try event(.leftMouseUp, at: points.last!, window: window))
            #expect(completed == Selection(displayID: 42, rect: .init(x: 20, y: 30, width: 100, height: 60), shape: .freehand(points: points)))
            #expect(!window.isVisible)
        }
    }

    private func event(_ type: NSEvent.EventType, at point: CGPoint, window: NSWindow) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                       windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }
}
