import Foundation

@main
struct Mote {
    @MainActor
    static func main() {
        do {
            let output = try CLI().run(arguments: Array(CommandLine.arguments.dropFirst()))
            if !output.isEmpty {
                print(output)
            }
        } catch {
            FileHandle.standardError.write(Data("mote: \(error.localizedDescription)\n".utf8))
            exit(MoteExitStatus.code(for: error))
        }
    }
}
