import Darwin
import Foundation

@MainActor
struct VMBackgroundSupervisor {
    enum SupervisorError: LocalizedError {
        case cannotDetach(String)

        var errorDescription: String? {
            switch self {
            case .cannotDetach(let message):
                return "Unable to detach the VM supervisor: \(message)."
            }
        }
    }

    let store: VMStore

    func run(name: String) throws {
        guard Darwin.setsid() >= 0 || errno == EPERM else {
            throw SupervisorError.cannotDetach(String(cString: strerror(errno)))
        }

        let bundle = try store.load(named: name)
        let lock = try VMLock(bundle: bundle)
        store.clearRuntime(for: bundle)

        let console = try BackgroundConsole(bundle: bundle)
        let control = try VMControlChannel(url: bundle.controlURL)
        let configuration = try VMConfigurationBuilder().build(
            for: bundle,
            consoleInput: console.guestInput,
            consoleOutput: console.guestOutput,
            options: .init(graphicalDisplay: true)
        )
        let runner = VMRunner(configuration: configuration)

        defer {
            store.clearRuntime(for: bundle)
            control.stop()
            console.stop()
        }

        try withExtendedLifetime(lock) {
            _ = try runner.run(
                didStart: {
                    try store.writeRuntime(
                        VMRuntime(pid: getpid(), startedAt: Date()),
                        for: bundle
                    )
                },
                poll: {
                    control.poll { command in
                        switch command {
                        case "display":
                            runner.showDisplay(title: bundle.record.name)
                        case "stop":
                            runner.requestGracefulStop(source: "mote stop")
                        case "force-stop":
                            runner.forceStop()
                        default:
                            guard let request = VMISOControl.Request(command: command) else {
                                break
                            }
                            let respond: (Error?) -> Void = { error in
                                do {
                                    try VMISOControl.respond(to: request, bundle: bundle, error: error)
                                } catch {
                                    FileHandle.standardError.write(
                                        Data("mote: Unable to report ISO operation: \(error.localizedDescription)\n".utf8)
                                    )
                                }
                            }
                            switch request {
                            case .mount(_, let path):
                                runner.mountISO(path: path, completion: respond)
                            case .unmount:
                                runner.unmountISO(completion: respond)
                            }
                        }
                    }
                }
            )
        }
    }
}
