/// Physical orientation of the Magic Mouse while its surface acts as a trackpad.
/// X points to the mouse's right edge; Y points toward its narrow front end.
enum TrackpadModeOrientation: Int {
    case upright = 0
    case narrowEndRight = 1
    case narrowEndLeft = 2

    /// Rotate a screen-space vector (X right, Y down) with the mouse.
    func rotated(x: Double, y: Double) -> (x: Double, y: Double) {
        switch self {
        case .upright: return (x, y)
        case .narrowEndRight: return (-y, x)
        case .narrowEndLeft: return (y, -x)
        }
    }

    /// Correct the aspect ratio of single-finger cursor movement after rotation.
    /// The reciprocal factors preserve the overall gain while changing X:Y shape.
    /// Upright movement is intentionally unchanged.
    func cursorDelta(x: Double, y: Double, sidewaysAspectRatio: Double) -> (x: Double, y: Double) {
        let vector = rotated(x: x, y: y)
        guard self != .upright else { return vector }
        let factor = max(0.5, min(sidewaysAspectRatio, 3.0)).squareRoot()
        return (vector.x * factor, vector.y / factor)
    }

    /// Native MT Y grows toward the narrow front. Scroll values point in the
    /// opposite direction from finger movement when content follows the hand.
    func scrollDelta(contactDX: Double, contactDY: Double, gain: Double) -> (x: Double, y: Double) {
        let finger = rotated(x: contactDX, y: -contactDY)
        return (-finger.x * gain, -finger.y * gain)
    }
}
