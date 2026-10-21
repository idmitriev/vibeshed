import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
// Line-buffered, so our lines and the ssh/ffmpeg output we hand the
// terminal come out in order even when piped.
setvbuf(stdout, nil, _IOLBF, 0)

if arguments.first == "agent" {
    MainActor.assumeIsolated {
        Agent.main(Array(arguments.dropFirst()))
    }
} else {
    exit(HostCLI.main(arguments))
}
