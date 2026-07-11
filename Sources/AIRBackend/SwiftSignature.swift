import Foundation
import GPUSwift

// Parses a kernel's Swift *source* signature into a `KernelInterface`.
//
// This is a driver-side concern — deliberately NOT part of the compiler fork.
// It recovers what `swiftc -O` drops from the IR (argument names, pointee
// types) and lets the author state binding intent with lightweight per-parameter
// markers that mirror the eventual attributes:
//
//     public func indices(_ gridPos: UnsafeMutablePointer<UInt32>,  // @binding(0)
//                         _ localPos: UnsafeMutablePointer<UInt32>,  // @binding(1)
//                         _ gid: UInt32,                             // @threadPositionInGrid
//                         _ lid: UInt32) {                           // @threadPositionInThreadgroup
//
// When the compiler carries real `@Binding` / `@ThreadPositionInGrid`
// attributes, this parser is retired and the frontend supplies the interface
// directly. Same information, authoritative source.
public enum SwiftSignature {

    /// Map a Swift type spelling to its AIR `arg_type_name` + size/align.
    static let dataTypes: [String: DataType] = [
        "Float": .float, "Float32": .float,
        "SIMD2<Float>": .float2, "SIMD3<Float>": .float3, "SIMD4<Float>": .float4,
        "UInt32": .uint, "Int32": .int, "Float16": .half,
    ]

    /// Map a Swift scalar type to the AIR type name a builtin reflects.
    static let builtinTypeNames: [String: String] = [
        "UInt32": "uint", "Int32": "int",
        "SIMD2<UInt32>": "uint2", "SIMD3<UInt32>": "uint3", "SIMD4<UInt32>": "uint4",
    ]

    struct RawParam { var name: String; var type: String; var marker: String? }

    /// Build the interface for `kernel` from Swift `source`.
    public static func parse(source: String, kernel: String, stage: Stage = .compute)
        throws -> KernelInterface
    {
        let params = try rawParams(source: source, kernel: kernel)
        var args: [Argument] = []
        var autoBuffer = 0

        for p in params {
            let marker = p.marker.map(parseMarker)

            if let (base, elem) = pointer(p.type) {
                // A bound buffer.
                guard let element = dataTypes[elem] else {
                    throw AIRGenError(message: "unsupported buffer element type '\(elem)' on '\(p.name)'")
                }
                var access: Access = base == .mutable ? .readWrite : .read
                var space: AddressSpace = .device
                var index = autoBuffer
                if let m = marker {
                    if m.const { access = .read }
                    if let s = m.space { space = s }
                    if let b = m.binding { index = b }
                    if m.builtin != nil {
                        throw AIRGenError(message: "'\(p.name)' is a pointer but marked as a builtin")
                    }
                }
                args.append(.buffer(index: index, space: space, access: access,
                                    element: element, name: p.name))
                autoBuffer = max(autoBuffer, index) + 1
            } else {
                // A scalar — must be a hardware builtin.
                let typeName = builtinTypeNames[p.type] ?? "uint"
                let builtin: Builtin
                if let b = marker?.builtin {
                    builtin = b
                } else {
                    // Fallback: a lone scalar is the grid thread position.
                    let scalarCount = params.filter { pointer($0.type) == nil }.count
                    guard scalarCount == 1 else {
                        throw AIRGenError(message:
                            "scalar '\(p.name)' needs a builtin marker (e.g. // @threadPositionInGrid) " +
                            "when a kernel has multiple scalar inputs")
                    }
                    builtin = .threadPositionInGrid
                }
                args.append(.builtin(builtin, typeName: typeName, name: p.name))
            }
        }
        return KernelInterface(name: kernel, stage: stage, arguments: args)
    }

    // MARK: - Type helpers

    enum PointerBase { case immutable, mutable }

    /// If `type` is a pointer, return its mutability and pointee spelling.
    static func pointer(_ type: String) -> (PointerBase, String)? {
        for (prefix, base) in [("UnsafeMutablePointer<", PointerBase.mutable),
                               ("UnsafePointer<", PointerBase.immutable)] {
            if type.hasPrefix(prefix), type.hasSuffix(">") {
                let inner = String(type.dropFirst(prefix.count).dropLast())
                return (base, inner.trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }

    // MARK: - Marker parsing

    struct Marker {
        var binding: Int?
        var space: AddressSpace?
        var const = false
        var builtin: Builtin?
    }

    /// Parse a `// @…`-style marker comment (already stripped of `//`).
    static func parseMarker(_ text: String) -> Marker {
        var m = Marker()
        // Tokens look like `@binding(2)`, `@const`, `@device`, `@threadPositionInGrid`.
        let tokens = text.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        for tok in tokens where tok.hasPrefix("@") {
            let body = String(tok.dropFirst())
            let name = body.contains("(") ? String(body[..<body.firstIndex(of: "(")!]) : body
            let arg = body.contains("(")
                ? String(body[body.index(after: body.firstIndex(of: "(")!)..<(body.firstIndex(of: ")") ?? body.endIndex)])
                : nil
            switch name {
            case "binding": m.binding = arg.flatMap { Int($0) }
            case "device": m.space = .device
            case "constant": m.space = .constant
            case "threadgroup": m.space = .threadgroup
            case "const": m.const = true
            default:
                if let b = Builtin(marker: name) { m.builtin = b }
            }
        }
        return m
    }

    // MARK: - Signature extraction

    /// Extract `(name, type, marker?)` per parameter for `func <kernel>` (or the
    /// `func` following `@_silgen_name("<kernel>")`).
    static func rawParams(source: String, kernel: String) throws -> [RawParam] {
        let lines = source.components(separatedBy: "\n")

        // Find the line index where the target func's signature begins.
        var funcLine: Int? = nil
        if let silgen = lines.firstIndex(where: { $0.contains("@_silgen_name(\"\(kernel)\")") }) {
            funcLine = lines[silgen...].firstIndex(where: { $0.contains("func ") })
        }
        if funcLine == nil {
            funcLine = lines.firstIndex(where: { $0.contains("func \(kernel)(") || $0.contains("func \(kernel) (") })
        }
        guard let start = funcLine else {
            throw AIRGenError(message: "could not find `func` for kernel '\(kernel)' in source")
        }

        // Gather signature lines until parenthesis depth returns to zero,
        // recording each line's trailing `//` comment.
        var entries: [(code: String, comment: String?)] = []
        var depth = 0, seenOpen = false, done = false
        for line in lines[start...] {
            let (code, comment) = splitComment(line)
            entries.append((code, comment))
            for c in code {
                if c == "(" { depth += 1; seenOpen = true }
                else if c == ")" { depth -= 1 }
            }
            if seenOpen && depth == 0 { done = true; break }
        }
        guard done else { throw AIRGenError(message: "unterminated signature for '\(kernel)'") }

        // Restrict to the text between the outermost parens, then split params on
        // top-level commas while attaching each line's comment to the param that
        // closes on it.
        var params: [RawParam] = []
        var cur = ""
        var curComment: String? = nil
        depth = 0
        var started = false
        for (code, comment) in entries {
            var lineHadComma = false
            for c in code {
                if c == "(" { depth += 1; if depth == 1 && !started { started = true; continue } }
                if !started { continue }
                if c == ")" { depth -= 1; if depth == 0 { break } }
                if c == "," && depth == 1 {
                    params.append(makeParam(cur, marker: comment ?? curComment))
                    cur = ""; curComment = nil; lineHadComma = true
                } else {
                    cur.append(c)
                }
            }
            // A comment on a line whose comma already closed the param decorates
            // that closed param (handled above). Otherwise it belongs to `cur`.
            if let cm = comment, !lineHadComma { curComment = cm }
            else if let cm = comment, lineHadComma, let last = params.indices.last, params[last].marker == nil {
                params[last].marker = cm
            }
        }
        let tail = cur.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { params.append(makeParam(cur, marker: curComment)) }
        return params
    }

    /// Parse `_ name: Type` (or `label name: Type`, or `name: Type`).
    static func makeParam(_ raw: String, marker: String?) -> RawParam {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let colon = trimmed.firstIndex(of: ":") ?? trimmed.endIndex
        let namePart = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
        let type = colon == trimmed.endIndex ? "" :
            String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        // The internal name is the last identifier before the colon.
        let name = namePart.split(separator: " ").last.map(String.init) ?? namePart
        return RawParam(name: name, type: type, marker: marker)
    }

    /// Split a source line into (code, trailing-comment-without-slashes).
    static func splitComment(_ line: String) -> (String, String?) {
        guard let r = line.range(of: "//") else { return (line, nil) }
        let comment = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        return (String(line[..<r.lowerBound]), comment.isEmpty ? nil : comment)
    }
}
