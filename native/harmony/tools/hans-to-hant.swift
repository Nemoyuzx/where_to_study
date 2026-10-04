import Foundation

let input = FileHandle.standardInput.readDataToEndOfFile()
let strings = try JSONDecoder().decode([String].self, from: input)
let converted = strings.map { source in
    source.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? source
}
let output = try JSONEncoder().encode(converted)
FileHandle.standardOutput.write(output)
