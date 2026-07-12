import GPUSwift

// Mapping from Swift type spellings to AIR data types. Shared by the source
// parser (`SwiftSignature`, transitional) and the compiler-metadata reader
// (`SwiftGPUKernelMetadata`), so both agree on how e.g. `SIMD4<Float>` reflects.
enum SwiftTypeMapping {
    /// Buffer element / scalar Swift type -> AIR `arg_type_name` + size/align.
    static let dataTypes: [String: DataType] = [
        "Float": .float, "Float32": .float,
        "SIMD2<Float>": .float2, "SIMD3<Float>": .float3, "SIMD4<Float>": .float4,
        "UInt32": .uint, "Int32": .int, "Float16": .half,
    ]

    /// Swift scalar type -> the AIR type name a builtin reflects.
    static let builtinTypeNames: [String: String] = [
        "UInt32": "uint", "Int32": "int",
        "SIMD2<UInt32>": "uint2", "SIMD3<UInt32>": "uint3", "SIMD4<UInt32>": "uint4",
    ]

    enum PointerBase { case immutable, mutable }

    /// If `type` is a Swift pointer spelling, return its mutability + pointee.
    /// The pointee may carry a GPU address-space qualifier (`device Float`);
    /// strip it — the element type is what the AIR metadata reflects, and the
    /// address space rides natively on the pointer type.
    static func pointer(_ type: String) -> (PointerBase, String)? {
        for (prefix, base) in [("UnsafeMutablePointer<", PointerBase.mutable),
                               ("UnsafePointer<", PointerBase.immutable)] {
            if type.hasPrefix(prefix), type.hasSuffix(">") {
                var inner = String(type.dropFirst(prefix.count).dropLast())
                    .trimmingCharacters(in: .whitespaces)
                for qualifier in ["device ", "constant ", "threadgroup ", "thread "] {
                    if inner.hasPrefix(qualifier) {
                        inner = String(inner.dropFirst(qualifier.count))
                            .trimmingCharacters(in: .whitespaces)
                    }
                }
                return (base, inner)
            }
        }
        return nil
    }
}
