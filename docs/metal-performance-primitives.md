# MetalPerformancePrimitives as a Swift package

MetalPerformancePrimitives (MPP) are the *in-shader* performance primitives —
simdgroup matrices, tensor ops — as opposed to MetalPerformanceShaders (MPS),
which is host-side prebuilt-kernel dispatch. MPP belongs in this project as a
**shader-side library** built on the core codegen; MPS is plain Metal interop
and lives elsewhere.

## "Static linking" on the GPU: there is no linker — you inline

A kernel's `.metallib` inlines everything into its entry point; there is no
runtime linker resolving library symbols on the GPU (see the AIR backend guide,
doc 08). So MPP primitives cannot be a separately-compiled library you link
against — they must be **inlined into the kernel**, exactly like MSL's
MetalPerformancePrimitives headers are header-only C++ templates.

Swift already has the "header-only, inlined into the client" mechanisms:

- **`@inlinable` + `@_alwaysEmitIntoClient`** — the function body lives in the
  module interface and is emitted/inlined at each call site, not left as an
  external symbol to link. A kernel calling `matmul(...)` gets the body inlined
  into its own AIR.
- The actual **hardware intrinsics** (`air.simdgroup_matrix_multiply_accumulate`,
  `air.simdgroup_matrix_8x8_load`, …) appear as `declare`s in the kernel's AIR
  and are resolved by `metal-as`/`metallib`/the driver as **AIR builtins** —
  that's the hardware, not code we ship.

So "static linking" = *source-inline the Swift wrappers + emit the intrinsic
declarations*; the toolchain resolves the intrinsics. The MPP package is
compiled/imported as part of shader compilation; its inlinable bodies flow into
the kernel module.

## Feasibility: verified (2026-07-12)

Hand-written AIR that `declare`s and calls the four 8×8 simdgroup-matrix
intrinsics (`_load`, `_init_filled`, `_multiply_accumulate`, `_store`) —
assembles (`metal-as`), packages (`metallib`), validates (`metal-validate`), and
**runs correctly on the GPU** (verified `C = A·B` for 8×8). The declare-and-call
model works end-to-end. Reference: `metal-air-documentation` doc 12 + harness
`16_simdgroup_matrix`.

**Key constraint found:** the simdgroup intrinsics require **typed** pointer
operands (`float addrspace(1)*`); an opaque `ptr addrspace(1)` operand crashes
the driver's back-end compiler (even though `metal-validate` passes). Our
compiler (LLVM 21) emits opaque pointers, so the MPP codegen path must ensure the
intrinsic call operands are typed — either emit typed pointers for those calls,
or have the AIR-emission step retype them. (Ordinary device buffer access is
fine with opaque pointers; this is specific to the matrix intrinsics.)

## Package implementation

A SwiftPM library target `MetalPerformancePrimitives` (shader-side):

1. **GPU-safe value types** — `SimdgroupMatrix<T, rows, cols>`, tensor
   descriptors. Fixed-size, no heap (they satisfy the GPU subset). A
   `simdgroup_matrix` is `<64 x float>` at the IR level (an 8×8 = 2048-bit
   vector); representing it likely needs a small amount of **compiler `Builtin`
   support** (it's an opaque AIR matrix type, and needs
   `"min-legal-vector-width"="2048"` on any kernel that uses it) — the rest is
   library.
2. **Operations** as `@inlinable @_alwaysEmitIntoClient` functions that call the
   intrinsics via `@_silgen_name("air.simdgroup_matrix_8x8_multiply_accumulate…")`
   external declarations — pure library, no compiler change for the call itself.
3. **Threadgroup-backed storage** (shared matrix tiles) uses the `@Threadgroup`
   address space (see `docs/address-spaces.md`) — a reason address spaces came
   first.
4. Ground every intrinsic name/signature in `metal-air-documentation` **doc 12**
   (simdgroup matrices) and **doc 13** (tensors) — don't guess the ABI. Note the
   matrix "descriptor" args are `<2 x i64>` vectors: for an 8×8 load with
   element-stride 8, no transpose, origin (0,0), they are `<8,8>`, `<1,8>`,
   `<0,0>`.

Split: **mostly a library** of inlinable intrinsic wrappers, plus a small amount
of **compiler support** for the opaque matrix/tensor types (a `Builtin`) and the
typed-pointer requirement above. Tensors (doc 13) additionally lower to a call to
an externally-defined `__tensorops_impl_*` rather than an inline intrinsic —
that path needs its own linking story (a provided tensor-ops object), TBD.
