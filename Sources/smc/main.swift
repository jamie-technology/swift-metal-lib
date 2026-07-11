import Foundation
import GPUSwift
import AIRBackend

// smc — the swift-metal compiler driver.
//
//   smc <shader.swift> --kernel <name> [-o out.metallib]
//       [--emit-air] [--emit-ir] [--keep] [--swiftc <path>]
//
// Pipeline:  swiftc -emit-ir -O  ->  IR→AIR transform  ->  metal-as  ->  metallib

struct Options {
    var source: String = ""
    var kernels: [String] = []
    var output: String?
    var emitAIR = false
    var emitIR = false
    var keepIntermediates = false
    var swiftcPath: String?
}

func die(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("smc: error: \(msg)\n".utf8))
    exit(1)
}

func parseArgs() -> Options {
    var o = Options()
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let a = it.next() {
        switch a {
        case "--kernel", "-k":
            guard let v = it.next() else { die("--kernel needs a value") }
            o.kernels.append(v)
        case "-o", "--output":
            guard let v = it.next() else { die("-o needs a value") }
            o.output = v
        case "--emit-air": o.emitAIR = true
        case "--emit-ir": o.emitIR = true
        case "--keep": o.keepIntermediates = true
        case "--swiftc":
            guard let v = it.next() else { die("--swiftc needs a value") }
            o.swiftcPath = v
        case "-h", "--help":
            print("""
            smc — compile Swift GPU kernels to a Metal .metallib

            USAGE: smc <shader.swift> --kernel <name> [options]

            OPTIONS:
              -k, --kernel <name>   Name of a kernel entry point (repeatable)
              -o, --output <path>   Output .metallib (default: <shader>.metallib)
              --emit-air            Also write the generated textual AIR (.air.ll)
              --emit-ir             Also write swiftc's raw LLVM IR (.ll)
              --keep                Keep intermediate files
              --swiftc <path>       Path to the GPU-capable swiftc
              -h, --help            Show this help
            """)
            exit(0)
        default:
            if a.hasPrefix("-") { die("unknown option '\(a)'") }
            o.source = a
        }
    }
    if o.source.isEmpty { die("no input shader (try --help)") }
    if o.kernels.isEmpty { die("specify at least one --kernel") }
    if o.kernels.count > 1 { die("multiple kernels per module not yet supported; pass one --kernel") }
    return o
}

/// Run a subprocess, returning stdout; abort with stderr on failure.
@discardableResult
func run(_ launchPath: String, _ args: [String], capture: Bool = true) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: launchPath)
    p.arguments = args
    let out = Pipe(), err = Pipe()
    if capture { p.standardOutput = out; p.standardError = err }
    do { try p.run() } catch { die("failed to launch \(launchPath): \(error)") }
    p.waitUntilExit()
    let stdout = capture ? String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) : ""
    if p.terminationStatus != 0 {
        let e = capture ? String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) : ""
        die("`\(([launchPath] + args).joined(separator: " "))` failed (\(p.terminationStatus))\n\(e)")
    }
    return stdout
}

func findSwiftc(_ override: String?) -> String {
    if let o = override { return o }
    if let e = ProcessInfo.processInfo.environment["SWIFT_GPU_SWIFTC"] { return e }
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let guess = "\(home)/Developer/swift-gpu-fork/build/Ninja-RelWithDebInfoAssert+swift-DebugAssert/swift-macosx-arm64/bin/swiftc"
    if FileManager.default.isExecutableFile(atPath: guess) { return guess }
    die("could not locate a GPU-capable swiftc; set SWIFT_GPU_SWIFTC or pass --swiftc")
}

func xcrun(_ tool: String) -> String {
    run("/usr/bin/xcrun", ["--find", tool]).trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Main

let opts = parseArgs()
let swiftc = findSwiftc(opts.swiftcPath)
let kernelName = opts.kernels[0]

let srcURL = URL(fileURLWithPath: opts.source)
let stem = srcURL.deletingPathExtension().lastPathComponent
let dir = srcURL.deletingLastPathComponent()
func sibling(_ ext: String) -> String { dir.appendingPathComponent("\(stem).\(ext)").path }

// 1. swiftc -emit-ir -O  (the fork's frontend does the Swift → LLVM lowering)
let ir = run(swiftc, ["-emit-ir", "-O", "-parse-as-library", opts.source])
if opts.emitIR {
    try? ir.write(toFile: sibling("ll"), atomically: true, encoding: .utf8)
    print("smc: wrote \(sibling("ll"))")
}

// 2. IR → AIR
let (air, iface) = try! IRToAIR.generate(ir: ir, kernelName: kernelName)
let airPath = opts.keepIntermediates || opts.emitAIR ? sibling("air.ll")
    : FileManager.default.temporaryDirectory.appendingPathComponent("\(stem)-\(kernelName).air.ll").path
try! air.write(toFile: airPath, atomically: true, encoding: .utf8)
if opts.emitAIR { print("smc: wrote \(airPath)") }

// 3. metal-as  →  .air (bitcode)
let airBitcode = airPath.replacingOccurrences(of: ".air.ll", with: ".air")
run(xcrun("metal-as"), [airPath, "-o", airBitcode])

// 4. metallib  →  .metallib
let output = opts.output ?? sibling("metallib")
run(xcrun("metallib"), [airBitcode, "-o", output])

if !opts.keepIntermediates {
    try? FileManager.default.removeItem(atPath: airBitcode)
    if !opts.emitAIR { try? FileManager.default.removeItem(atPath: airPath) }
}

// Report the interface we lowered — the binding contract the host must match.
print("smc: compiled '\(kernelName)' → \(output)")
for (i, arg) in iface.arguments.enumerated() {
    switch arg {
    case let .buffer(index, space, access, element, name):
        print("       arg[\(i)] \(name): \(space) \(access) \(element.airName)* @ buffer(\(index))")
    case let .builtin(b, name):
        print("       arg[\(i)] \(name): \(b.rawValue)")
    }
}
