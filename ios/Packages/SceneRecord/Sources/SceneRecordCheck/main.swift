import Foundation
import SceneRecord

private let help = """
Usage: scene-record-check [--compact] [-o OUTPUT | --output OUTPUT] INPUT

Validate capture-first SceneRecord schema 0.1.0 and emit normalized JSON.
INPUT is a JSON filepath, or - for UTF-8 stdin. JSON goes to stdout unless
-o/--output supplies a filepath. Output is written only after validation.
--compact omits pretty-print whitespace. --help prints this help.
Exit status: 0 success/help, 1 invalid input or I/O error, 2 invalid arguments.

Nulls and unknown source fields are retained. Numbers use Double precision.
Gate values: pass, warn, blocked. R0/blocked records require empty analysis.
No referenced assets are opened. This is not field validation or NorthResolver.
"""

private func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data(("scene-record-check: " + message + "\n").utf8))
    exit(code)
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--help"] || arguments == ["-h"] {
    print(help)
    exit(0)
}
var input: String?
var output: String?
var compact = false
var index = 0
while index < arguments.count {
    let argument = arguments[index]
    if argument == "--compact" {
        compact = true
    } else if argument == "-o" || argument == "--output" {
        index += 1
        guard index < arguments.count, output == nil else { fail("missing or repeated output filepath; use --help", code: 2) }
        output = arguments[index]
    } else if argument.hasPrefix("-") && argument != "-" {
        fail("unknown option \(argument); use --help", code: 2)
    } else {
        guard input == nil else { fail("expected one input filepath; use --help", code: 2) }
        input = argument
    }
    index += 1
}
guard let input else { fail("missing input filepath; use --help", code: 2) }
do {
    let data = try input == "-" ? FileHandle.standardInput.readToEnd() ?? Data() : Data(contentsOf: URL(fileURLWithPath: input))
    let document = try SceneRecordDocument(data: data)
    var result = try document.encoded(prettyPrinted: !compact)
    result.append(10)
    if let output {
        try result.write(to: URL(fileURLWithPath: output), options: .atomic)
    } else {
        FileHandle.standardOutput.write(result)
    }
} catch {
    fail(String(describing: error), code: 1)
}
