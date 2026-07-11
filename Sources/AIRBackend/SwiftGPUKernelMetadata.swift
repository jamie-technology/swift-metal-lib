import Foundation
import GPUSwift

// Reads the `!swiftgpu.kernels` named metadata that the GPU-aware swiftc emits
// for each `@Compute` function, and turns it into a `KernelInterface`.
//
// This is what retires `SwiftSignature.swift`: the binding contract now comes
// from the compiler (which saw the real `@Compute` / `@Binding` /
// `@ThreadPositionInGrid` attributes) instead of from re-parsing the Swift text.
//
// Emitted shape (see IRGenModule::emitSwiftGPUKernelMetadata in the fork):
//
//   !swiftgpu.kernels = !{!10}
//   !10 = !{ptr @add, !"compute", !11}
//   !11 = !{!12, !13, !14}
//   !12 = !{i32 0, !"buffer", i32 0, !"UnsafePointer<Float>", !"a"}   ; astIdx, role, slot, swiftType, name
//   !14 = !{i32 2, !"threadPositionInGrid", i32 -1, !"UInt32", !"gid"}
public enum SwiftGPUKernelMetadata {

    /// Returns the interface for `kernel`, or nil if no `!swiftgpu.kernels`
    /// metadata is present (so callers can fall back to source parsing).
    public static func parse(ir: String, kernel: String) throws -> KernelInterface? {
        let lines = ir.components(separatedBy: "\n")

        // Index every numbered metadata node: "!42 = !{…}" -> "!{…}".
        var nodes: [String: String] = [:]
        for line in lines {
            guard line.hasPrefix("!"), let eq = line.range(of: " = ") else { continue }
            let id = String(line[..<eq.lowerBound]).trimmingCharacters(in: .whitespaces)
            guard id.count > 1, id.dropFirst().allSatisfy(\.isNumber) else { continue }
            nodes[id] = String(line[eq.upperBound...]).trimmingCharacters(in: .whitespaces)
        }

        guard let named = lines.first(where: { $0.hasPrefix("!swiftgpu.kernels") }) else {
            return nil
        }

        for kref in metadataRefs(in: named) {
            guard let node = nodes[kref] else { continue }
            let fields = tupleFields(node)                 // [ptr @add, !"compute", !NN]
            guard fields.count >= 3 else { continue }
            guard symbolName(fields[0]) == kernel else { continue }
            guard let argsNode = nodes[fields[2]] else {
                throw AIRGenError(message: "kernel '\(kernel)' metadata missing argument list")
            }
            var args: [Argument] = []
            var autoBuffer = 0
            for aref in metadataRefs(in: argsNode) {
                guard let anode = nodes[aref] else { continue }
                args.append(try parseArgument(tupleFields(anode), autoBuffer: &autoBuffer))
            }
            return KernelInterface(name: kernel, stage: .compute, arguments: args)
        }
        return nil
    }

    // MARK: - Argument node

    private static func parseArgument(_ fields: [String], autoBuffer: inout Int) throws -> Argument {
        guard fields.count >= 5 else {
            throw AIRGenError(message: "malformed swiftgpu argument node: \(fields)")
        }
        let role = string(fields[1])
        let slot = int(fields[2])
        let swiftType = string(fields[3])
        let argName = string(fields[4])

        if role == "buffer" {
            guard let (base, elem) = SwiftTypeMapping.pointer(swiftType) else {
                throw AIRGenError(message: "buffer argument is not a pointer type: '\(swiftType)'")
            }
            guard let element = SwiftTypeMapping.dataTypes[elem] else {
                throw AIRGenError(message: "unsupported buffer element type '\(elem)'")
            }
            let access: Access = base == .mutable ? .readWrite : .read
            let index = slot >= 0 ? slot : autoBuffer
            autoBuffer = max(autoBuffer, index) + 1
            return .buffer(index: index, space: .device, access: access,
                           element: element, name: argName)
        }

        guard let builtin = Builtin(marker: role) else {
            throw AIRGenError(message: "unknown builtin role '\(role)'")
        }
        let typeName = SwiftTypeMapping.builtinTypeNames[swiftType] ?? "uint"
        return .builtin(builtin, typeName: typeName, name: argName)
    }

    // MARK: - Metadata text helpers

    /// All `!<digits>` references in a piece of metadata text, in order.
    private static func metadataRefs(in text: String) -> [String] {
        var refs: [String] = []
        var rest = Substring(text)
        while let bang = rest.range(of: "!") {
            let after = rest[bang.upperBound...]
            let digits = after.prefix { $0.isNumber }
            if !digits.isEmpty { refs.append("!" + digits) }
            rest = after.dropFirst(digits.count)
        }
        return refs
    }

    /// Split `!{a, b, c}` (or `{a, b, c}`) into top-level fields, honoring
    /// quoted strings and angle/bracket nesting.
    private static func tupleFields(_ text: String) -> [String] {
        var t = text.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("!") { t.removeFirst() }
        guard t.hasPrefix("{"), t.hasSuffix("}") else { return [] }
        t = String(t.dropFirst().dropLast())
        var fields: [String] = [], cur = "", depth = 0, inString = false
        for c in t {
            if c == "\"" { inString.toggle(); cur.append(c); continue }
            if inString { cur.append(c); continue }
            if c == "<" || c == "(" || c == "[" { depth += 1 }
            else if c == ">" || c == ")" || c == "]" { depth -= 1 }
            if c == "," && depth == 0 { fields.append(cur.trimmingCharacters(in: .whitespaces)); cur = "" }
            else { cur.append(c) }
        }
        if !cur.trimmingCharacters(in: .whitespaces).isEmpty {
            fields.append(cur.trimmingCharacters(in: .whitespaces))
        }
        return fields
    }

    /// Extract a string from a `!"…"` field.
    private static func string(_ field: String) -> String {
        if let q1 = field.firstIndex(of: "\""), let q2 = field.lastIndex(of: "\""), q1 < q2 {
            return String(field[field.index(after: q1)..<q2])
        }
        return field
    }

    /// Extract the integer from an `i32 N` field.
    private static func int(_ field: String) -> Int {
        let digits = field.split(separator: " ").last.map(String.init) ?? field
        return Int(digits) ?? -1
    }

    /// Extract the symbol from a `ptr @name` field.
    private static func symbolName(_ field: String) -> String {
        if let at = field.firstIndex(of: "@") {
            return String(field[field.index(after: at)...]).trimmingCharacters(in: .whitespaces)
        }
        return field.trimmingCharacters(in: .whitespaces)
    }
}
