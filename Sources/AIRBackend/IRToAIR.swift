import Foundation
import GPUSwift

struct AIRGenError: Error, CustomStringConvertible {
    let message: String
    var description: String { "swift-metal: \(message)" }
}

/// Transforms the LLVM IR that `swiftc -emit-ir -O` produces for a kernel-shaped
/// Swift function into a loadable AIR module.
///
/// The Swift IR for a leaf compute function is already ~10 mechanical edits from
/// valid AIR (see docs/08). This performs exactly those edits:
///   1. swap the target triple / datalayout for AIR's,
///   2. drop Swift-runtime globals & metadata (reflection, module flags),
///   3. flatten Swift's single-field wrapper structs (`%TSf` -> `float`,
///      `%Ts5SIMD4VySfG` -> `<4 x float>`) using the module's own typedefs,
///   4. strip `swiftcc` and rewrite bound pointers into the right `addrspace`,
///      propagating the address space through derived pointers,
///   5. emit the AIR entry-point + argument metadata contract.
///
/// The binding contract comes from a `KernelInterface` (parsed from the Swift
/// source, or inferred from the signature when none is supplied).
public enum IRToAIR {

    public static func generate(ir rawIR: String,
                                kernelName: String,
                                stage: Stage = .compute,
                                interface providedInterface: KernelInterface? = nil)
        throws -> (air: String, interface: KernelInterface)
    {
        // (3) Flatten Swift scalar/vector wrapper structs to their payload type.
        let ir = flattenWrapperTypes(rawIR)
        let lines = ir.components(separatedBy: "\n")

        // Locate the kernel `define` and its body.
        guard let defineIdx = lines.firstIndex(where: {
            $0.hasPrefix("define ") && $0.contains("@\(kernelName)(")
        }) else {
            throw AIRGenError(message: "no `define` for kernel '\(kernelName)' in emitted IR")
        }
        guard let endIdx = lines[defineIdx...].firstIndex(of: "}") else {
            throw AIRGenError(message: "unterminated function body for '\(kernelName)'")
        }
        let params = try parseParams(fromDefine: lines[defineIdx], kernel: kernelName)
        let bodyLines = Array(lines[(defineIdx + 1)..<endIdx])

        // The binding contract: provided (from source) or inferred.
        let interface: KernelInterface
        if let p = providedInterface {
            guard p.arguments.count == params.count else {
                throw AIRGenError(message:
                    "interface for '\(kernelName)' has \(p.arguments.count) args but IR has \(params.count)")
            }
            interface = p
        } else {
            interface = inferInterface(name: kernelName, stage: stage, params: params)
        }

        // Map each buffer parameter's SSA value to its address space.
        var rootSpace: [String: AddressSpace] = [:]
        for (pos, arg) in interface.arguments.enumerated() {
            if case let .buffer(_, space, _, _, name) = arg {
                guard params[pos].isPointer else {
                    throw AIRGenError(message: "'\(name)' is a buffer but IR parameter \(pos) is not a pointer")
                }
                rootSpace[params[pos].ssa] = space
            }
        }

        // (4b) Rewrite the signature.
        let newParamText = zip(params, interface.arguments).map { p, arg -> String in
            switch arg {
            case let .buffer(_, space, _, _, _):
                return "ptr addrspace(\(space.rawValue)) noundef \"air-buffer-no-alias\" \(p.ssa)"
            case .builtin:
                return "\(p.typeTok) noundef \(p.ssa)"
            }
        }.joined(separator: ", ")
        let newDefine = "define void @\(kernelName)(\(newParamText)) #0 {"

        // (4c) Thread address spaces through the body.
        let newBody = rewriteBody(bodyLines, roots: rootSpace)

        // (5) Metadata contract.
        let (namedMD, nodes) = emitMetadata(for: interface)

        var out = ""
        out += "; swift-metal generated AIR for kernel '\(kernelName)'\n"
        out += "source_filename = \"\(kernelName)\"\n"
        out += "target datalayout = \"\(AIR.dataLayout)\"\n"
        out += "target triple = \"\(AIR.triple)\"\n\n"
        out += newDefine + "\n"
        out += newBody.map { "  " + $0.trimmingCharacters(in: .whitespaces) }
                       .filter { $0.trimmingCharacters(in: .whitespaces) != "" }
                       .joined(separator: "\n") + "\n"
        out += "}\n\n"
        out += "attributes #0 = { \(AIR.functionAttributes) }\n\n"
        out += AIR.moduleTail(entryNamedMD: namedMD, entryNodes: nodes) + "\n"
        return (out, interface)
    }

    // MARK: - Wrapper-type flattening

    /// Swift wraps scalars/vectors in single-field structs (`%TSf = type <{ float
    /// }>`, `%Ts5SIMD4VySfG = type <{ %TSf12SIMD4StorageV }>`). Resolve every such
    /// name to its underlying LLVM type and substitute it away, so GEPs read as
    /// `getelementptr <4 x float>, …`. Multi-field structs are left untouched.
    static func flattenWrapperTypes(_ ir: String) -> String {
        var raw: [String: String] = [:]       // %Name -> inner type text
        for line in ir.components(separatedBy: "\n") {
            guard let eq = line.range(of: " = type "), line.hasPrefix("%") else { continue }
            let name = String(line[..<eq.lowerBound]).trimmingCharacters(in: .whitespaces)
            var body = String(line[eq.upperBound...]).trimmingCharacters(in: .whitespaces)
            // Unwrap `<{ … }>` or `{ … }`.
            if body.hasPrefix("<{") && body.hasSuffix("}>") {
                body = String(body.dropFirst(2).dropLast(2))
            } else if body.hasPrefix("{") && body.hasSuffix("}") {
                body = String(body.dropFirst().dropLast())
            } else { continue }
            body = body.trimmingCharacters(in: .whitespaces)
            // Only single-field wrappers (no top-level comma).
            if hasTopLevelComma(body) { continue }
            raw[name] = body
        }
        guard !raw.isEmpty else { return ir }

        // Resolve transitively to a non-wrapper (primitive/vector) type.
        func resolve(_ t: String, _ depth: Int = 0) -> String {
            guard depth < 16, t.hasPrefix("%"), let inner = raw[t] else { return t }
            return resolve(inner, depth + 1)
        }
        let resolved = Dictionary(uniqueKeysWithValues: raw.keys.map { ($0, resolve($0)) })

        // Drop the typedef lines, then substitute names (longest first, at token
        // boundaries so `%TSf` doesn't clobber `%TSf12SIMD4StorageV`).
        var out = ir.components(separatedBy: "\n").filter { line in
            !(line.hasPrefix("%") && line.contains(" = type "))
        }.joined(separator: "\n")
        for name in resolved.keys.sorted(by: { $0.count > $1.count }) {
            out = boundaryReplace(out, name, resolved[name]!)
        }
        return out
    }

    static func hasTopLevelComma(_ s: String) -> Bool {
        var depth = 0
        for c in s {
            if c == "<" || c == "{" || c == "(" || c == "[" { depth += 1 }
            else if c == ">" || c == "}" || c == ")" || c == "]" { depth -= 1 }
            else if c == "," && depth == 0 { return true }
        }
        return false
    }

    // MARK: - Signature parsing

    struct ParsedParam { var typeTok: String; var attrs: String; var ssa: String; var isPointer: Bool }

    static func parseParams(fromDefine define: String, kernel: String) throws -> [ParsedParam] {
        guard let open = define.range(of: "@\(kernel)(")?.upperBound else {
            throw AIRGenError(message: "malformed define for '\(kernel)'")
        }
        var depth = 1, idx = open
        while idx < define.endIndex, depth > 0 {
            let c = define[idx]
            if c == "(" { depth += 1 } else if c == ")" { depth -= 1; if depth == 0 { break } }
            idx = define.index(after: idx)
        }
        guard depth == 0 else { throw AIRGenError(message: "unbalanced parens in signature of '\(kernel)'") }
        let paramStr = String(define[open..<idx])
        if paramStr.trimmingCharacters(in: .whitespaces).isEmpty { return [] }

        var parts: [String] = [], cur = ""
        depth = 0
        for c in paramStr {
            if c == "(" { depth += 1 } else if c == ")" { depth -= 1 }
            if c == "," && depth == 0 { parts.append(cur); cur = "" } else { cur.append(c) }
        }
        if !cur.trimmingCharacters(in: .whitespaces).isEmpty { parts.append(cur) }

        return try parts.map { raw in
            let toks = raw.split(separator: " ").map(String.init)
            guard let typeTok = toks.first, let ssa = toks.last(where: { $0.hasPrefix("%") }) else {
                throw AIRGenError(message: "cannot parse parameter '\(raw)'")
            }
            let attrs = toks.dropFirst().filter { !$0.hasPrefix("%") }.joined(separator: " ")
            return ParsedParam(typeTok: typeTok, attrs: attrs, ssa: ssa, isPointer: typeTok == "ptr")
        }
    }

    // MARK: - Inference (fallback when no source interface is supplied)

    static func inferInterface(name: String, stage: Stage, params: [ParsedParam]) -> KernelInterface {
        var args: [Argument] = []
        var bufIndex = 0
        let scalarCount = params.filter { !$0.isPointer }.count
        for (pos, p) in params.enumerated() {
            if p.isPointer {
                let access: Access = p.attrs.contains("readonly") ? .read : .readWrite
                args.append(.buffer(index: bufIndex, space: .device, access: access,
                                    element: .float, name: "arg\(pos)"))
                bufIndex += 1
            } else {
                let name = scalarCount == 1 ? "gid" : "arg\(pos)"
                args.append(.builtin(.threadPositionInGrid, typeName: "uint", name: name))
            }
        }
        return KernelInterface(name: name, stage: stage, arguments: args)
    }

    // MARK: - Body rewriting (address-space propagation)

    /// Thread each buffer's address space through every derived pointer, and
    /// normalise GEP flags metal-as's LLVM does not accept (`nuw`).
    static func rewriteBody(_ body: [String], roots: [String: AddressSpace]) -> [String] {
        var space = roots
        var changed = true
        while changed {
            changed = false
            for line in body {
                guard let eq = line.range(of: " = ") else { continue }
                let dest = line[..<eq.lowerBound].trimmingCharacters(in: .whitespaces)
                guard dest.hasPrefix("%"), space[dest] == nil else { continue }
                let rhs = String(line[eq.upperBound...])
                guard rhs.contains("getelementptr") || rhs.contains("bitcast")
                        || rhs.contains("phi ptr") || rhs.contains("select") else { continue }
                if let s = space.first(where: { referencesValue(rhs, $0.key) })?.value {
                    space[dest] = s; changed = true
                }
            }
        }
        return body.map { line in
            var l = line.replacingOccurrences(of: "getelementptr inbounds nuw ", with: "getelementptr inbounds ")
            l = l.replacingOccurrences(of: "getelementptr nuw ", with: "getelementptr ")
            l = expandSplats(l)
            for (v, s) in space { l = replaceOperand(in: l, value: v, space: s) }
            return l
        }
    }

    /// metal-as's LLVM predates the `splat (T V)` constant spelling. Rewrite it to
    /// the classic elementwise vector constant `<T V, T V, …>`, taking the width
    /// from the instruction's `<N x …>` result type.
    static func expandSplats(_ line: String) -> String {
        var l = line
        while let s = l.range(of: "splat (") {
            var depth = 1, idx = s.upperBound
            while idx < l.endIndex, depth > 0 {
                let c = l[idx]
                if c == "(" { depth += 1 } else if c == ")" { depth -= 1; if depth == 0 { break } }
                idx = l.index(after: idx)
            }
            guard depth == 0 else { break }
            let inner = String(l[s.upperBound..<idx]).trimmingCharacters(in: .whitespaces)
            let n = vectorWidth(String(l[..<s.lowerBound])) ?? 1
            let expanded = "<" + Array(repeating: inner, count: n).joined(separator: ", ") + ">"
            l.replaceSubrange(s.lowerBound...idx, with: expanded)
        }
        return l
    }

    /// Extract N from the first `<N x …>` in `text`.
    static func vectorWidth(_ text: String) -> Int? {
        guard let lt = text.range(of: "<") else { return nil }
        let after = text[lt.upperBound...]
        let digits = after.prefix { $0.isNumber || $0 == " " }.trimmingCharacters(in: .whitespaces)
        guard after.dropFirst(digits.count).trimmingCharacters(in: .whitespaces).hasPrefix("x") else { return nil }
        return Int(digits)
    }

    static func referencesValue(_ text: String, _ value: String) -> Bool {
        var rest = Substring(text)
        while let r = rest.range(of: value) {
            let after = r.upperBound
            if after == rest.endIndex { return true }
            let c = rest[after]
            if !(c.isLetter || c.isNumber || c == "_") { return true }
            rest = rest[after...]
        }
        return false
    }

    /// Rewrite `ptr <value>` operand uses to `ptr addrspace(n) <value>`.
    static func replaceOperand(in line: String, value: String, space: AddressSpace) -> String {
        let needle = "ptr \(value)"
        var result = "", rest = Substring(line)
        while let r = rest.range(of: needle) {
            let after = r.upperBound
            let ok = after == rest.endIndex || !(rest[after].isLetter || rest[after].isNumber || rest[after] == "_")
            result += rest[..<r.lowerBound]
            result += ok ? "ptr addrspace(\(space.rawValue)) \(value)" : needle
            rest = rest[after...]
        }
        result += rest
        return result
    }

    /// Boundary-aware substring replace for LLVM type/value names.
    static func boundaryReplace(_ text: String, _ name: String, _ replacement: String) -> String {
        var result = "", rest = Substring(text)
        while let r = rest.range(of: name) {
            let after = r.upperBound
            let ok = after == rest.endIndex || !(rest[after].isLetter || rest[after].isNumber || rest[after] == "_")
            result += rest[..<r.lowerBound]
            result += ok ? replacement : name
            rest = rest[after...]
        }
        result += rest
        return result
    }

    // MARK: - Metadata emission

    static func airAccess(_ a: Access) -> String {
        switch a {
        case .read: return "air.read"
        case .write: return "air.write"
        case .readWrite: return "air.read_write"
        }
    }

    static func emitMetadata(for iface: KernelInterface) -> (namedMD: String, nodes: String) {
        let kernelNode = 9, attrsNode = 10, argListNode = 11, firstArgNode = 12
        var nodeLines: [String] = []
        nodeLines.append("!\(kernelNode) = !{ptr @\(iface.name), !\(attrsNode), !\(argListNode)}")
        nodeLines.append("!\(attrsNode) = !{}")
        let argList = iface.arguments.indices.map { "!\(firstArgNode + $0)" }.joined(separator: ", ")
        nodeLines.append("!\(argListNode) = !{\(argList)}")

        for (pos, arg) in iface.arguments.enumerated() {
            let id = firstArgNode + pos
            switch arg {
            case let .buffer(index, space, access, element, name):
                nodeLines.append(
                    "!\(id) = !{i32 \(pos), !\"air.buffer\", " +
                    "!\"air.location_index\", i32 \(index), i32 1, " +
                    "!\"\(airAccess(access))\", " +
                    "!\"air.address_space\", i32 \(space.rawValue), " +
                    "!\"air.arg_type_size\", i32 \(element.size), " +
                    "!\"air.arg_type_align_size\", i32 \(element.align), " +
                    "!\"air.arg_type_name\", !\"\(element.airName)\", " +
                    "!\"air.arg_name\", !\"\(name)\"}")
            case let .builtin(builtin, typeName, name):
                nodeLines.append(
                    "!\(id) = !{i32 \(pos), !\"\(builtin.rawValue)\", " +
                    "!\"air.arg_type_name\", !\"\(typeName)\", " +
                    "!\"air.arg_name\", !\"\(name)\"}")
            }
        }
        return ("!\(iface.stage.rawValue) = !{!\(kernelNode)}", nodeLines.joined(separator: "\n"))
    }
}
