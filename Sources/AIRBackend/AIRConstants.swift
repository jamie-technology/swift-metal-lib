// Fixed pieces of an AIR module, lifted verbatim from a reference module
// (metal-air-documentation/harnesses/compute/00_minimal_add). These encode
// AIR's ABI/target facts that a backend must reproduce exactly; see
// docs/08-emitting-air-a-backend-guide.md.
enum AIR {
    /// AIR's data layout — note `n8:16:32` (no native i64). Copied verbatim.
    static let dataLayout = "e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v24:32:32-v32:32:32-v48:64:64-v64:64:64-v96:128:128-v128:128:128-v192:256:256-v256:256:256-v512:512:512-v1024:1024:1024-n8:16:32"

    /// The AIR target triple. `air64_v28` is the AIR ISA version.
    static let triple = "air64_v28-apple-macosx26.0.0"

    /// Function attributes for a kernel body. Deliberately conservative.
    static let functionAttributes = "convergent mustprogress nofree norecurse nounwind willreturn"

    /// Module-level resource ceilings + version metadata. `%%KERNELS%%`,
    /// `%%NODES%%` and `%%ENTRY%%` are filled in by the generator.
    static func moduleTail(entryNamedMD: String, entryNodes: String) -> String {
        """
        !llvm.module.flags = !{!0, !1, !2, !3, !4, !5, !6, !7, !8}
        \(entryNamedMD)
        !air.compile_options = !{!100, !101, !102}
        !air.version = !{!103}
        !air.language_version = !{!104}

        !0 = !{i32 2, !"SDK Version", [2 x i32] [i32 26, i32 4]}
        !1 = !{i32 1, !"wchar_size", i32 4}
        !2 = !{i32 7, !"frame-pointer", i32 2}
        !3 = !{i32 7, !"air.max_device_buffers", i32 31}
        !4 = !{i32 7, !"air.max_constant_buffers", i32 31}
        !5 = !{i32 7, !"air.max_threadgroup_buffers", i32 31}
        !6 = !{i32 7, !"air.max_textures", i32 128}
        !7 = !{i32 7, !"air.max_read_write_textures", i32 8}
        !8 = !{i32 7, !"air.max_samplers", i32 16}
        \(entryNodes)
        !100 = !{!"air.compile.denorms_disable"}
        !101 = !{!"air.compile.fast_math_enable"}
        !102 = !{!"air.compile.framebuffer_fetch_enable"}
        !103 = !{i32 2, i32 8, i32 0}
        !104 = !{!"Metal", i32 3, i32 2, i32 0}
        """
    }
}
