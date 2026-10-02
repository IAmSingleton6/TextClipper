enum CaptureMode: Equatable {
    case box
    case circle

    var selectionShape: SelectionShape {
        self == .box ? .rectangle : .ellipse
    }
}
