import CoreGraphics

/// Global AppKit screen points. Origin (0, 0) is on the primary display; x increases right, y increases up.
struct ScreenPoint: Equatable, Sendable {
    let appKitGlobalPoint: CGPoint

    init(appKitGlobalPoint: CGPoint) {
        self.appKitGlobalPoint = appKitGlobalPoint
    }

    init(x: CGFloat, y: CGFloat) {
        self.appKitGlobalPoint = CGPoint(x: x, y: y)
    }

    static let zero = Self(x: 0, y: 0)
    var x: CGFloat {
        self.appKitGlobalPoint.x
    }

    var y: CGFloat {
        self.appKitGlobalPoint.y
    }
}

/// Global AppKit screen rect. Origin (0, 0) is on the primary display; x increases right, y increases up.
struct ScreenRect: Equatable, Sendable {
    let appKitGlobalRect: CGRect

    init(appKitGlobalRect: CGRect) {
        self.appKitGlobalRect = appKitGlobalRect
    }

    init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.appKitGlobalRect = CGRect(x: x, y: y, width: width, height: height)
    }

    static let zero = Self(x: 0, y: 0, width: 0, height: 0)
    var minX: CGFloat {
        self.appKitGlobalRect.minX
    }

    var minY: CGFloat {
        self.appKitGlobalRect.minY
    }

    var maxX: CGFloat {
        self.appKitGlobalRect.maxX
    }

    var maxY: CGFloat {
        self.appKitGlobalRect.maxY
    }

    var midX: CGFloat {
        self.appKitGlobalRect.midX
    }

    var midY: CGFloat {
        self.appKitGlobalRect.midY
    }

    var width: CGFloat {
        self.appKitGlobalRect.width
    }

    var height: CGFloat {
        self.appKitGlobalRect.height
    }

    var size: CGSize {
        self.appKitGlobalRect.size
    }

    func contains(_ point: ScreenPoint) -> Bool {
        self.appKitGlobalRect.contains(point.appKitGlobalPoint)
    }
}

/// Selection-view points local to one display. Origin is bottom-left; x increases right, y increases up.
struct DisplayPoint: Equatable, Sendable {
    let displayLocalPoint: CGPoint

    init(x: CGFloat, y: CGFloat) {
        self.displayLocalPoint = CGPoint(x: x, y: y)
    }

    static let zero = Self(x: 0, y: 0)
    var x: CGFloat {
        self.displayLocalPoint.x
    }

    var y: CGFloat {
        self.displayLocalPoint.y
    }
}

/// Selection-view rect local to one display. Origin is bottom-left; x increases right, y increases up.
struct DisplayRect: Equatable, Sendable {
    let displayLocalRect: CGRect

    init(displayLocalRect: CGRect) {
        self.displayLocalRect = displayLocalRect
    }

    init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.displayLocalRect = CGRect(x: x, y: y, width: width, height: height)
    }

    static let zero = Self(x: 0, y: 0, width: 0, height: 0)
    var minX: CGFloat {
        self.displayLocalRect.minX
    }

    var minY: CGFloat {
        self.displayLocalRect.minY
    }

    var maxX: CGFloat {
        self.displayLocalRect.maxX
    }

    var maxY: CGFloat {
        self.displayLocalRect.maxY
    }

    var width: CGFloat {
        self.displayLocalRect.width
    }

    var height: CGFloat {
        self.displayLocalRect.height
    }

    func insetBy(dx: CGFloat, dy: CGFloat) -> Self {
        Self(displayLocalRect: self.displayLocalRect.insetBy(
            dx: dx,
            dy: dy,
        ))
    }
}

/// Full-display CGImage pixels for cropping. Origin is top-left; x increases right, y increases down.
struct ImagePixelRect: Equatable, Sendable {
    let cgImageCropRect: CGRect

    init(cgImageCropRect: CGRect) {
        self.cgImageCropRect = cgImageCropRect
    }

    init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.cgImageCropRect = CGRect(x: x, y: y, width: width, height: height)
    }

    var minX: CGFloat {
        self.cgImageCropRect.minX
    }

    var maxY: CGFloat {
        self.cgImageCropRect.maxY
    }

    var isEmpty: Bool {
        self.cgImageCropRect.isEmpty
    }
}

/// Cropped-image-local pixels for drawing the freehand mask in CGContext. Origin is bottom-left; x increases right, y
/// increases up.
struct CroppedImagePixelPoint: Equatable, Sendable {
    let maskContextPoint: CGPoint

    init(x: CGFloat, y: CGFloat) {
        self.maskContextPoint = CGPoint(x: x, y: y)
    }

    var x: CGFloat {
        self.maskContextPoint.x
    }

    var y: CGFloat {
        self.maskContextPoint.y
    }
}
