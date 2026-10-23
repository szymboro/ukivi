import FilterKit
import Foundation

// Usage: filterkit <output.json> <list.txt>...
// Converts filter list files the same way the app does on the phone.

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count >= 2, let output = arguments.first else {
    FileHandle.standardError.write(Data("usage: filterkit <output.json> <list.txt>...\n".utf8))
    exit(2)
}

let texts = try arguments.dropFirst().map { path in
    String(decoding: try Data(contentsOf: URL(fileURLWithPath: path)), as: UTF8.self)
}
let start = Date()
let (rules, stats) = FilterConverter.convert(texts)
let seconds = Date().timeIntervalSince(start)
try SafariRule.encode(rules).write(to: URL(fileURLWithPath: output))
print("\(stats.converted) filters converted into \(rules.count) Safari rules; skipped \(stats.skipped) (\(String(format: "%.2f", seconds))s)")
