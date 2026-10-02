enum CaptureMode: Equatable {
    case box
    case freehand

    func accepts(_ shape: SelectionShape) -> Bool {
        switch (self, shape) {
        case (.box, .rectangle), (.freehand, .freehand): true
        default: false
        }
    }
}
