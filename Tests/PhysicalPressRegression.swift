import CoreGraphics
import Foundation

enum PhysicalPressRegression {
    static func run(_ remap: (CGEventType, CGEvent, UInt64?) -> Bool) {
        AppSettings.shared.registerDefaults()
        let shared = SharedState.shared
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }
        func options(zones: Bool = false, press: Bool = true) {
            UserDefaults.standard.register(defaults: [
                AppSettings.Key.trackpadTapZones: zones,
                AppSettings.Key.trackpadPressDragEnabled: press
            ])
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
        func event(_ type: CGEventType) -> CGEvent {
            CGEvent(mouseEventSource: nil, mouseType: type,
                    mouseCursorPosition: .zero, mouseButton: .right)!
        }
        shared.trackpadModeActive = true
        options()
        let down = event(.rightMouseDown)
        check(remap(.rightMouseDown, down, 123), "Magic Mouse secondary press should become a left press")
        check(down.type == .leftMouseDown && down.getIntegerValueField(.mouseEventButtonNumber) == 0,
              "Remapped press must carry left event type and button number")
        check(shared.leftButtonDown, "Surface movement should see the remapped button held")

        let otherUp = event(.rightMouseUp)
        check(!remap(.rightMouseUp, otherUp, 999), "Another mouse must not release the converted press")
        shared.trackpadModeActive = false
        options(press: false)
        let up = event(.rightMouseUp)
        check(remap(.rightMouseUp, up, 123) && up.type == .leftMouseUp,
              "Matching release must remain paired after mode or option changes")
        check(!shared.leftButtonDown, "Release must clear the held-left state")

        shared.trackpadModeActive = true
        options()
        check(!remap(.rightMouseDown, event(.rightMouseDown), 999), "Ordinary mouse right click must remain unchanged")
        check(!remap(.rightMouseDown, event(.rightMouseDown), nil), "Unknown sender must pass through")
        options(zones: true)
        check(!remap(.rightMouseDown, event(.rightMouseDown), 123), "Optional left/right-zone mode must retain physical right click")
        options(press: false)
        check(!remap(.rightMouseDown, event(.rightMouseDown), 123), "Disabling press dragging must restore native buttons")
        shared.trackpadModeActive = false
        options()
        check(!remap(.rightMouseDown, event(.rightMouseDown), 123), "Outside trackpad mode physical buttons must remain native")
        print("PASS: \(checks) physical-press assertions; no events posted")
    }
}
