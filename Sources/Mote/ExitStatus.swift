import Darwin
import Foundation

enum MoteExitStatus {
    static func code(for error: Error) -> Int32 {
        if let error = error as? CLI.CLIError {
            switch error {
            case .usage, .installationAlreadyAttempted, .deletionRequiresForce:
                return EX_USAGE
            case .alreadyRunning, .stopTimedOut:
                return EX_TEMPFAIL
            case .notRunning, .cannotDeleteRunning:
                return EX_UNAVAILABLE
            }
        }

        if let error = error as? VMStore.StoreError {
            switch error {
            case .notFound, .missingComponent:
                return EX_NOINPUT
            case .corruptBundle:
                return EX_DATAERR
            case .invalidName, .alreadyExists:
                return EX_USAGE
            }
        }

        if let error = error as? InstallationMedia.MediaError {
            switch error {
            case .notFound:
                return EX_NOINPUT
            case .notISO, .unsupportedArchitecture, .unrecognizedArchitecture:
                return EX_DATAERR
            }
        }

        if error is ByteSize.ParseError { return EX_USAGE }
        if error is VMLock.LockError { return EX_TEMPFAIL }
        if error is VMProcessLauncher.LaunchError { return EX_UNAVAILABLE }
        if error is VMControlChannel.ControlError { return EX_UNAVAILABLE }
        if let error = error as? VMConfigurationBuilder.ConfigurationError {
            switch error {
            case .virtualizationUnsupported: return EX_UNAVAILABLE
            case .invalidDiskSize: return EX_CONFIG
            }
        }
        if error is CocoaError || error is POSIXError { return EX_IOERR }
        return EX_SOFTWARE
    }
}
