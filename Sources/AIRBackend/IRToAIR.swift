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
///   3. normalise Swift's wrapper struct types (`%TSf` -> `float`),
///   4. strip `swiftcc` and rewrite buffer pointers into `addrspace(1)`,
///      propagating the address space through derived pointers,
///   5. emit the AIR entry-point + argument metadata contract.
///
/// Scope: a single, fully-inlined leaf kernel over `device` buffers plus one
/// thread-position builtin — i.e. the shape the frontend currently lowers to.
/// Textures, threadgroup memory, atomics, and helper calls are future work.
public enum IRToAIR {
    /// Swift emits primitive values wrapped in single-field structs (`%TSf = type
    /// <{ float }>`). GEPs over them are equivalent to GEPs over the scalar.
    static let swiftScalarWrappers: [String: String] = [
        "%TSf": "float", "%TSd": "double",
        "%TSs": "i16", "%TSi": "i64", "%TSu": "i64",
        "%Ts6UInt32V": "i32", "%Ts5Int32V": "i32",
    ]

    public static func generate(ir rawIR: String, kernelName: String, stage: Stage = .compute)
        throws -> (air: String, interface: KernelInterface)
    {
        // (3) Normalise Swift scalar-wrapper struct types away.
        var ir = rawIR
        for (wrapper, scalar) in swiftScalarWrappers {
            ir = ir.replacingOccurrences(of: wrapper, with: scalar)
        }

        let lines = ir.components(separatedBy: "\n")

        // Locate the kernel `define`.
        guard let defineIdx = lines.firstIndex(where: { line in
            line.hasPrefix("define ") && line.contains("@\(kernelName)(")
        }) else {
            throw AIRGenError(message: "no `define` for kernel '\(kernelName)' in emitted IR")
        }

        // Extract the function body (up to and including the closing `}`).
        guard let endIdx = lines[defineIdx...].firstIndex(where: { $0 == "}" }) else {
            throw AIRGenError(message: "unterminated function body for '\(kernelName)'")
        }

        let defineLine = lines[defineIdx]
        let bodyLines = Array(lines[(defineIdx + 1)..<endIdx])

        // (4a) Parse the signature and infer the kernel interface.
        let params = try parseParams(fromDefine: defineLine, kernel: kernelName)
        let (interface, bufferSSANames) = inferInterface(name: kernelName, stage: stage, params: params)

        // (4b) Rewrite the signature: strip `swiftcc`/`local_unnamed_addr`, retype
        //      buffer pointers, keep the builtin scalars.
        let newParamText = params.map { p -> String in
            if p.isPointer {
                return "ptr addrspace(1) noundef \"air-buffer-no-alias\" \(p.ssa)"
            } else {
                return "\(p.typeTok) noundef \(p.ssa)"
            }
        }.joined(separator: ", ")
        let newDefine = "define void @\(kernelName)(\(newParamText)) #0 {"

        // (4c) Rewrite the body: normalise GEP flags and thread the device
        //      address space through every buffer-derived pointer.
        let newBody = rewriteBody(bodyLines, deviceRoots: Set(bufferSSANames))

        // (5) Build the metadata contract.
        let (namedMD, nodes) = emitMetadata(for: interface)

        // Reassemble a minimal module.
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

    // MARK: - Signature parsing

    struct ParsedParam { var typeTok: String; var attrs: String; var ssa: String; var isPointer: Bool }

    static func parseParams(fromDefine define: String, kernel: String) throws -> [ParsedParam] {
        guard let open = define.range(of: "@\(kernel)(")?.upperBound else {
            throw AIRGenError(message: "malformed define for '\(kernel)'")
        }
        // Find the matching close paren from `open`, tracking nesting (attrs like
        // `captures(none)` / `memory(argmem: readwrite)` contain parens).
        var depth = 1
        var idx = open
        while idx < define.endIndex, depth > 0 {
            let c = define[idx]
            if c == "(" { depth += 1 } else if c == ")" { depth -= 1; if depth == 0 { break } }
            idx = define.index(after: idx)
        }
        guard depth == 0 else { throw AIRGenError(message: "unbalanced parens in signature of '\(kernel)'") }
        let paramStr = String(define[open..<idx])
        if paramStr.trimmingCharacters(in: .whitespaces).isEmpty { return [] }

        // Depth-aware split on top-level commas.
        var parts: [String] = []
        var cur = ""
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

    // MARK: - Inference

    /// Infer a `KernelInterface` from the signature: pointer params become
    /// `device` buffers (slot-indexed in order; access from readonly/writeonly),
    /// and a lone trailing scalar becomes `thread_position_in_grid`.
    static func inferInterface(name: String, stage: Stage, params: [ParsedParam])
        -> (KernelInterface, [String])
    {
        var args: [Argument] = []
        var bufferSSA: [String] = []
        var bufIndex = 0
        let scalarCount = params.filter { !$0.isPointer }.count

        for (pos, p) in params.enumerated() {
            if p.isPointer {
                let access: Access
                if p.attrs.contains("readonly") { access = .read }
                else if p.attrs.contains("writeonly") { access = .readWrite } // Metal binds writes as read_write
                else { access = .readWrite }
                args.append(.buffer(index: bufIndex, space: .device, access: access,
                                    element: .float, name: "arg\(pos)"))
                bufferSSA.append(p.ssa)
                bufIndex += 1
            } else {
                // MVP: a single scalar input is the grid thread position.
                let name = scalarCount == 1 ? "gid" : "arg\(pos)"
                args.append(.builtin(.threadPositionInGrid, name: name))
            }
        }
        return (KernelInterface(name: name, stage: stage, arguments: args), bufferSSA)
    }

    // MARK: - Body rewriting

    /// Thread `addrspace(1)` through every pointer derived from a device buffer,
    /// and normalise GEP flags metal-as's LLVM does not accept (`nuw`).
    static func rewriteBody(_ body: [String], deviceRoots: Set<String>) -> [String] {
        // Fixpoint: a value is a device pointer if it is a root, or a
        // getelementptr/bitcast/phi/select of a device pointer.
        var dev = deviceRoots
        var changed = true
        while changed {
            changed = false
            for line in body {
                guard let eq = line.range(of: " = ") else { continue }
                let dest = line[..<eq.lowerBound].trimmingCharacters(in: .whitespaces)
                guard dest.hasPrefix("%"), !dev.contains(dest) else { continue }
                let rhs = line[eq.upperBound...]
                guard rhs.contains("getelementptr") || rhs.contains("bitcast")
                        || rhs.contains("phi ptr") || rhs.contains("select") else { continue }
                // Any device-pointer operand referenced on the RHS taints dest.
                if dev.contains(where: { referencesValue(String(rhs), $0) }) {
                    dev.insert(dest); changed = true
                }
            }
        }

        return body.map { line in
            var l = line.replacingOccurrences(of: "getelementptr inbounds nuw ",
                                              with: "getelementptr inbounds ")
            l = l.replacingOccurrences(of: "getelementptr nuw ", with: "getelementptr ")
            // Annotate operand uses of device pointers with the address space.
            for v in dev {
                l = replaceOperand(in: l, value: v)
            }
            return l
        }
    }

    /// Whether `text` references SSA value `value` as a whole token.
    static func referencesValue(_ text: String, _ value: String) -> Bool {
        guard let r = text.range(of: value) else { return false }
        let after = r.upperBound
        if after < text.endIndex {
            let c = text[after]
            if c.isLetter || c.isNumber || c == "_" { return false } // e.g. %1 vs %10
        }
        return true
    }

    /// Rewrite `ptr <value>` operand uses to `ptr addrspace(1) <value>`.
    static func replaceOperand(in line: String, value: String) -> String {
        var result = ""
        var rest = Substring(line)
        let needle = "ptr \(value)"
        while let r = rest.range(of: needle) {
            // Guard the token boundary after the value (avoid %1 matching %10).
            let after = r.upperBound
            let ok: Bool
            if after < rest.endIndex {
                let c = rest[after]
                ok = !(c.isLetter || c.isNumber || c == "_")
            } else { ok = true }
            result += rest[..<r.lowerBound]
            if ok {
                result += "ptr addrspace(1) \(value)"
            } else {
                result += needle
            }
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

    /// Emit the `!air.kernel` (or vertex/fragment) named metadata plus every node
    /// it references, numbered from !9 (module flags occupy !0–!8).
    static func emitMetadata(for iface: KernelInterface) -> (namedMD: String, nodes: String) {
        let kernelNode = 9
        let attrsNode = 10
        let argListNode = 11
        let firstArgNode = 12

        var nodeLines: [String] = []
        nodeLines.append("!\(kernelNode) = !{ptr @\(iface.name), !\(attrsNode), !\(argListNode)}")
        nodeLines.append("!\(attrsNode) = !{}")

        let argNodeIDs = iface.arguments.indices.map { firstArgNode + $0 }
        let argList = argNodeIDs.map { "!\($0)" }.joined(separator: ", ")
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
            case let .builtin(builtin, name):
                nodeLines.append(
                    "!\(id) = !{i32 \(pos), !\"\(builtin.rawValue)\", " +
                    "!\"air.arg_type_name\", !\"\(builtin.argTypeName)\", " +
                    "!\"air.arg_name\", !\"\(name)\"}")
            }
        }

        let namedMD = "!\(iface.stage.rawValue) = !{!\(kernelNode)}"
        return (namedMD, nodeLines.joined(separator: "\n"))
    }
}
