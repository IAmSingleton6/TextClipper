import CoreGraphics
@testable import ScreenText
import Testing

@MainActor
struct CaptureControllerTests {
    @Test func `toggling an idle session opens capture on the current display`() {
        let capture = CaptureFixture(onEvent: { capture, event in
            if case let .started(display) = event {
                #expect(display.id == testDisplay.id)
                #expect(capture.state == .toolbar)
            }
        })

        // WHEN
        capture.toggle()

        // THEN
        #expect(capture.isActive)
        #expect(capture.toolbarIsVisible)
        #expect(capture.selectionIsVisible)
        #expect(capture.activityChanges == [true])
        #expect(capture.lifecycleEvents == ["started", "active"])
        #expect(capture.results.isEmpty)
    }

    @Test func `toggling an active session closes capture UI`() {
        let capture = CaptureFixture()

        // GIVEN
        capture.start()

        // WHEN
        capture.toggle()

        // THEN
        #expect(capture.isIdle)
        #expect(!capture.toolbarIsVisible)
        #expect(!capture.selectionIsVisible)
        #expect(!capture.escape.isListening)
        #expect(capture.activityChanges == [true, false])
        #expect(capture.toolbar.hideCount == 1)
        #expect(capture.results.isEmpty)
    }

    @Test func `toggling a cancelled session opens a new capture`() {
        let capture = CaptureFixture()

        // GIVEN
        capture.toggle()
        capture.toggle()

        // WHEN
        capture.toggle()

        // THEN
        #expect(capture.isActive)
        #expect(capture.toolbarIsVisible)
        #expect(capture.selectionIsVisible)
        #expect(capture.activityChanges == [true, false, true])
        #expect(capture.lifecycleEvents == ["started", "active", "inactive", "started", "active"])
        #expect(capture.toolbar.showCount == 2)
        #expect(capture.toolbar.hideCount == 1)
        #expect(capture.results.isEmpty)
    }

    @Test(arguments: [CaptureState.toolbar, .selecting(.box)])
    func `starting an active session does not reopen capture UI`(state: CaptureState) {
        let capture = CaptureFixture()

        // GIVEN
        capture.start()
        if state == .selecting(.box) {
            capture.beginSelection()
        }

        // WHEN
        capture.start()

        // THEN
        #expect(capture.state == state)
        #expect(capture.toolbarIsVisible == (state == .toolbar))
        #expect(capture.selectionIsVisible)
        #expect(capture.toolbar.showCount == 1)
        #expect(capture.selections.prepareCount == 1)
        #expect(capture.escape.starts == 1)
        #expect(capture.activityChanges == [true])
    }

    @Test func `cancelling an idle session has no effect`() {
        let capture = CaptureFixture()

        // WHEN
        capture.cancel()

        // THEN
        #expect(capture.isIdle)
        #expect(!capture.toolbarIsVisible)
        #expect(!capture.selectionIsVisible)
        #expect(capture.activityChanges.isEmpty)
        #expect(capture.toolbar.hideCount == 0)
        #expect(capture.escape.stops == 0)
        #expect(capture.results.isEmpty)
    }

    @Test func `cancelling an active session closes capture UI`() {
        let capture = CaptureFixture()

        // GIVEN
        capture.start()

        // WHEN
        capture.cancel()

        // THEN
        #expect(capture.isIdle)
        #expect(!capture.toolbarIsVisible)
        #expect(!capture.selectionIsVisible)
        #expect(!capture.escape.isListening)
        #expect(capture.activityChanges == [true, false])
        #expect(capture.toolbar.hideCount == 1)
        #expect(capture.escape.stops == 1)
        #expect(capture.results.isEmpty)
    }

    @Test func `cancelling an already cancelled session has no further effect`() {
        let capture = CaptureFixture()

        // GIVEN
        capture.start()
        capture.cancel()

        // WHEN
        capture.cancel()

        // THEN
        #expect(capture.isIdle)
        #expect(!capture.toolbarIsVisible)
        #expect(!capture.selectionIsVisible)
        #expect(capture.activityChanges == [true, false])
        #expect(capture.toolbar.hideCount == 1)
        #expect(capture.escape.stops == 1)
        #expect(capture.results.isEmpty)
    }

    @Test(arguments: [CaptureMode.box, .freehand])
    func `the persisted mode is available before capture starts`(mode: CaptureMode) {
        let capture = CaptureFixture(initialMode: mode)
        #expect(capture.selectedMode == mode)
        #expect(capture.isIdle)
    }

    @Test(arguments: [CaptureMode.box, .freehand])
    func `a session starts with the persisted mode`(mode: CaptureMode) {
        let capture = CaptureFixture(initialMode: mode)

        // WHEN
        capture.start()

        // THEN
        #expect(capture.toolbar.mode == mode)
        #expect(capture.selections.mode == mode)
        #expect(capture.selectedMode == mode)
    }

    @Test(arguments: [CaptureMode.box, .freehand])
    func `selecting a toolbar mode updates capture and saves the choice`(mode: CaptureMode) {
        let capture = CaptureFixture(initialMode: mode == .box ? .freehand : .box)

        // GIVEN
        capture.start()

        // WHEN
        capture.selectMode(mode)

        // THEN
        #expect(capture.selectedMode == mode)
        #expect(capture.toolbar.mode == mode)
        #expect(capture.selections.mode == mode)
        #expect(capture.savedMode == mode)
    }

    @Test(arguments: [CaptureMode.box, .freehand])
    func `the next session remembers the selected mode`(mode: CaptureMode) {
        let capture = CaptureFixture(initialMode: mode == .box ? .freehand : .box)

        // GIVEN
        capture.start()
        capture.selectMode(mode)
        capture.cancel()

        // WHEN
        capture.start()

        // THEN
        #expect(capture.selectedMode == mode)
        #expect(capture.toolbar.mode == mode)
        #expect(capture.selections.mode == mode)
        #expect(capture.toolbar.showCount == 2)
        #expect(capture.toolbar.hideCount == 1)
    }

    @Test func `a new session reloads externally changed preferences`() {
        let capture = CaptureFixture(initialMode: .freehand)

        // GIVEN
        capture.start()
        capture.selectMode(.box)
        capture.cancel()
        capture.savedMode = .freehand

        // WHEN
        capture.start()

        // THEN
        #expect(capture.selectedMode == .freehand)
        #expect(capture.toolbar.mode == .freehand)
        #expect(capture.selections.mode == .freehand)
    }

    @Test func `selecting a mode while idle leaves preferences unchanged`() {
        let capture = CaptureFixture()

        // WHEN
        capture.requestMode(.freehand)

        // THEN
        #expect(capture.isIdle)
        #expect(capture.selectedMode == .box)
        #expect(capture.savedMode == .box)
    }

    @Test func `the toolbar cancel button closes capture UI`() {
        let capture = CaptureFixture()

        // GIVEN
        capture.start()

        // WHEN
        capture.cancelFromToolbar()

        // THEN
        #expect(capture.isIdle)
        #expect(!capture.toolbarIsVisible)
        #expect(!capture.selectionIsVisible)
        #expect(!capture.escape.isListening)
        #expect(capture.activityChanges == [true, false])
        #expect(capture.results.isEmpty)
    }

    @Test func `a missing display leaves capture idle`() {
        let capture = CaptureFixture(display: nil)

        // WHEN
        capture.start()

        // THEN
        #expect(capture.isIdle)
        #expect(!capture.toolbarIsVisible)
        #expect(!capture.selectionIsVisible)
        #expect(capture.selections.prepareCount == 0)
        #expect(capture.escape.starts == 0)
        #expect(capture.events.isEmpty)
    }

    @Test func `an unavailable toolbar tears down the prepared selection`() {
        let capture = CaptureFixture(toolbarCanShow: false)

        // WHEN
        capture.start()

        // THEN
        #expect(capture.isIdle)
        #expect(!capture.toolbarIsVisible)
        #expect(!capture.selectionIsVisible)
        #expect(capture.selections.prepareCount == 1)
        #expect(capture.selections.hideCount == 1)
        #expect(capture.escape.starts == 0)
        #expect(capture.events.isEmpty)
    }

    @Test func `failed selection preparation leaves capture idle`() {
        let capture = CaptureFixture(selectionCanPrepare: false)

        // WHEN
        capture.start()

        // THEN
        #expect(capture.isIdle)
        #expect(!capture.selectionIsVisible)
        #expect(!capture.toolbarIsVisible)
        #expect(capture.toolbar.showCount == 0)
        #expect(capture.escape.starts == 0)
        #expect(capture.events.isEmpty)
    }

    @Test func `capture can retry after selection preparation fails`() {
        let capture = CaptureFixture(selectionCanPrepare: false)

        // GIVEN
        capture.start()
        capture.selections.canPrepare = true

        // WHEN
        capture.start()

        // THEN
        #expect(capture.state == .toolbar)
        #expect(capture.selectionIsVisible)
        #expect(capture.toolbarIsVisible)
        #expect(capture.activityChanges == [true])
    }

    @Test(arguments: [CaptureMode.box, .freehand])
    func `beginning selection hides the toolbar and keeps Escape available`(mode: CaptureMode) {
        let capture = CaptureFixture(initialMode: mode)

        // GIVEN
        capture.start()

        // WHEN
        capture.beginSelection()

        // THEN
        #expect(capture.state == .selecting(mode))
        #expect(!capture.toolbarIsVisible)
        #expect(capture.selectionIsVisible)
        #expect(capture.escape.isListening)
    }

    @Test(arguments: [CaptureMode.box, .freehand])
    func `selection locks the selected mode`(mode: CaptureMode) {
        let capture = CaptureFixture(initialMode: mode)

        // GIVEN
        capture.start()
        capture.beginSelection()

        // WHEN
        capture.requestMode(mode == .box ? .freehand : .box)

        // THEN
        #expect(capture.state == .selecting(mode))
        #expect(capture.selectedMode == mode)
        #expect(capture.savedMode == mode)
        #expect(capture.selections.mode == mode)
    }

    @Test func `cancelling selection returns to idle without a result`() {
        let capture = CaptureFixture()

        // GIVEN
        capture.start()
        capture.beginSelection()

        // WHEN
        capture.cancelSelection()

        // THEN
        #expect(capture.isIdle)
        #expect(!capture.selectionIsVisible)
        #expect(!capture.toolbarIsVisible)
        #expect(!capture.escape.isListening)
        #expect(capture.activityChanges == [true, false])
        #expect(capture.results.isEmpty)
    }

    @Test func `repeated selection starts do not restart the session`() {
        let capture = CaptureFixture()

        // GIVEN
        capture.start()
        capture.beginSelection()

        // WHEN
        capture.beginSelection()

        // THEN
        #expect(capture.state == .selecting(.box))
        #expect(capture.selectionIsVisible)
        #expect(capture.toolbar.hideCount == 1)
        #expect(capture.selections.prepareCount == 1)
        #expect(capture.escape.starts == 1)
        #expect(capture.activityChanges == [true])
    }

    @Test func `completion before selection begins is ignored`() {
        let capture = CaptureFixture()

        // GIVEN
        capture.start()

        // WHEN
        capture.completeSelection()

        // THEN
        #expect(capture.state == .toolbar)
        #expect(capture.toolbarIsVisible)
        #expect(capture.selectionIsVisible)
        #expect(capture.escape.isListening)
        #expect(capture.results.isEmpty)
    }
}
