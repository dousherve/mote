import AppKit
import Virtualization

@MainActor
final class VMDisplay {
    private let view: VZVirtualMachineView
    private let window: NSWindow

    init(virtualMachine: VZVirtualMachine, title: String) {
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
        view = VZVirtualMachineView(frame: frame)
        view.virtualMachine = virtualMachine
        view.capturesSystemKeys = true
        view.automaticallyReconfiguresDisplay = true

        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = view
        window.isReleasedWhenClosed = false
        window.center()
    }

    func show() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        application.finishLaunching()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        application.activate(ignoringOtherApps: true)
    }

    func processEvents(until limit: Date) {
        let application = NSApplication.shared
        guard let event = application.nextEvent(
            matching: .any,
            until: limit,
            inMode: .default,
            dequeue: true
        ) else { return }
        application.sendEvent(event)
    }

    func close() {
        window.close()
    }
}
