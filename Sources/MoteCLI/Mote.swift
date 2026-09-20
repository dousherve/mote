import Foundation

@main
struct Mote {
    static func main() {
        do {
            let output = try CLI().run(arguments: Array(CommandLine.arguments.dropFirst()))
            print(output)
        } catch {
            FileHandle.standardError.write(Data("mote: \(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
}
