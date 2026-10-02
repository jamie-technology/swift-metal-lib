# SIMD-group matrices

The `SIMDGroupMatrix` package (`packages/SIMDGroupMatrix`) exposes the
cooperative **8×8 matrix-multiply** primitive — one SIMD-group holds and
multiplies a whole tile — over the `air.simdgroup_matrix_8x8_*` intrinsics. It is
the building block for a hand-tiled GEMM.

```swift
@Compute
@_silgen_name("sgemm")
public func sgemm(@Binding(to: 0) @Device _ A: UnsafePointer<Float>,
                  @Binding(to: 1) @Device _ B: UnsafePointer<Float>,
                  @Binding(to: 2) @Device _ C: UnsafeMutablePointer<Float>) {
    let a = SIMDGroupMatrix.load(from: A)
    let b = SIMDGroupMatrix.load(from: B)
    let acc = SIMDGroupMatrix.filled(0)
    let c = a.multiplyAccumulate(b, acc)   // C = A·B + 0
    c.store(to: C)
}
```

Dispatch one threadgroup of 32 threads (one Apple SIMD-group) — every lane
participates in the same tile.

## API

| Call | Intrinsic |
| --- | --- |
| `SIMDGroupMatrix.filled(_:)` | `air.simdgroup_matrix_8x8_init_filled.v64f32.f32` |
| `SIMDGroupMatrix.load(from:elementsPerRow:)` | `air.simdgroup_matrix_8x8_load.v64f32.p1f32` |
| `a.multiplyAccumulate(b, c)` | `air.simdgroup_matrix_8x8_multiply_accumulate…` |
| `m.store(to:elementsPerRow:)` | `air.simdgroup_matrix_8x8_store.v64f32.p1f32` |

A matrix is a flat `<64 x float>` (`SIMD64<Float>`) held across the SIMD-group's
registers.

## The compiler work this needed

Unlike the other packages, matrices needed real compiler support, because Swift
passes a 256-byte `SIMD64<Float>` **indirectly** (`sret` + `dereferenceable(256)`
pointers) but the AIR intrinsics take and return it **by value** (`<64 x float>`).
All in the fork (see `docs/fork-changes.md`):

1. **`coerceValue` address-space fix** (`GenCall.cpp`) — passing a `@Device`
   (addrspace 1) pointer into the intrinsics tripped a plain `bitcast` across
   address spaces; it now uses an addrspace-cast.
2. **Indirect→by-value rewrite** (`IRGen.cpp`, `rewriteSimdgroupMatrixIntrinsics`)
   — each `air.simdgroup_matrix_*` call and declaration is rewritten to the
   by-value form; matrix values are forwarded as pure SSA (a simdgroup matrix
   lives in registers, so it must never touch a 2048-bit alloca), and the kernel
   gets `convergent` + `min-legal-vector-width=2048`.
3. **`.p1f32` pointer typing + dead `llvm.mem*` strip** (`FrontendTool.cpp`,
   `IRGen.cpp`) — the device pointer is typed `float addrspace(1)*` from the
   intrinsic suffix, and the now-dead `llvm.memcpy`/`memset` declarations are
   dropped so the module is fully typed.

## Example

`examples/sgemm` — C = A·B for 8×8 `Float` tiles, GPU-verified (A = identity, so
C == B). `examples/sgemm-intrinsic/sgemm.air.ll` is the hand-written reference
AIR these build toward. See
[metal-air-documentation `12-simdgroup-matrices`](https://github.com/jamie-technology/metal-air-documentation/blob/main/docs/12-simdgroup-matrices.md).
