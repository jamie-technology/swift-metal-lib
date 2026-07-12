# `swift-frontend -emit-air`

The GPU-capable `swift-frontend` emits **loadable Apple AIR directly** — no
external `smc` transform. Address spaces are already native (IRGen emits
`ptr addrspace(N)`); a normalization pass handles the remaining gaps to
`metal-as` (an ~LLVM 17 assembler) and the ABI metadata.

```sh
swift-frontend -emit-air -O -parse-as-library kernel.swift -o kernel.air.ll
xcrun metal-as kernel.air.ll -o kernel.air
xcrun metallib  kernel.air   -o kernel.metallib   # loadable, runs on GPU
```

Verified end-to-end on `examples/devadd` (`@Device` add kernel): native
`ptr addrspace(1)`, straight through `metal-as`/`metallib`, correct on GPU.

## How it works (fork)

`-emit-air` reuses the `EmitIR` frontend action plus an `IRGenOptions`
`EmitGPUDeviceIR` bit (set from the flag), so it needs no new `ActionType`
(avoids the exhaustive-switch churn). The bit adds a `SwiftGPUAIRNormalizePass`
into the LLVM pipeline **after all `-O` passes, before the module is printed**
(`lib/IRGen/IRGen.cpp`, `performLLVMOptimizations`). The pass, on the
`llvm::Module`:

1. Sets the AIR **triple + datalayout** (`air64_v28-apple-macosx26.0.0`).
2. Strips **`swiftcc`** (functions + call sites → C calling convention).
3. Strips parameter **`captures(none)`** (metal-as's LLVM has only `nocapture`).
4. Strips host/incompatible **function attributes** — the `memory(...)` effect
   spelling, `target-cpu`, `target-features`.
5. Clears **`nuw`** off `getelementptr`.
6. **Expands `splat (T V)` constants** to `insertelement` + `shufflevector`
   (metal-as's LLVM has no `splat` constant syntax) — built with `NoFolder` so
   the constant folder doesn't fold it straight back.
7. Converts **`!swiftgpu.kernels` → `!air.kernel`** + per-arg `air.buffer` /
   `air.<builtin>` nodes (parsing the pointer type for mutability → read vs
   read_write, `device`/`constant`/`threadgroup` → address space, and the
   pointee → AIR element type/size), and emits the module-level `air.*` facts
   (`air.max_*`, `air.version`, `air.language_version`).
8. Strips the **`"PIC Level"`** module flag — meaningless for a shader, and it
   crashes the driver back-end on constant-address-space globals (see
   `docs/address-spaces.md`).
9. Strips **`!prof` (branch_weights)** metadata off instructions — metal-as's
   LLVM rejects the newer `!{!"branch_weights", !"expected", …}` form, and
   profile weights are meaningless for a shader. This is what lets integer
   kernels assemble: Swift's overflow-checked `*`/`+` emit
   `llvm.*.with.overflow` plus a conditional branch to `llvm.trap`, and that
   branch carries the offending metadata (`examples/intmath`).

Address spaces are **not** rewritten here — IRGen already emits them natively
(see `docs/address-spaces.md`). That's why the pass is small.

## Typed (non-opaque) pointers

The fork's LLVM is **opaque-pointer only** (its `PointerType` stores just an
address space), so IRGen and the module pass can only produce `ptr addrspace(N)`.
But the Metal driver's back-end compiler expects real MSL-shaped AIR: **typed**
pointers (`float addrspace(1)*`) whose pointee matches the access type, and clean
element types. Opaque pointers happen to work for plain device-buffer kernels,
but typed pointers are required for e.g. simdgroup-matrix intrinsics.

Because typed pointers cannot exist in the in-memory module, the reconstruction
runs on the **printed textual AIR** (`rewriteAIRToTypedPointers` in
`lib/FrontendTool/FrontendTool.cpp`), applied in place after `performLLVM` and
before `metal-as`, for both `-emit-air` and `-emit-metallib`. It:

- **Flattens** Swift single-field wrapper structs to their MSL leaf: `%TSf`
  (`<{ float }>`) → `float`, the SIMD storage struct → `<4 x float>`,
  `InlineArray` → `[N x T]` (recursively; the constant initializer too).
- **Reconstructs pointee types** from the element types on `load`/`store`/`gep`,
  then rewrites function signatures, `getelementptr` (array-global accesses take
  the 2-index `[N x T]` form), `load`, `store`, and the `air.kernel` metadata
  function pointer to typed form.

Unmatched constructs are left unchanged (opaque), which `metal-as` still accepts;
extend the pass as new kernel shapes (calls with pointer args, `alloca`, casts)
appear.

## `-emit-metallib`: one command, no `smc`

`swift-frontend -emit-metallib` emits the AIR, then invokes `xcrun metal-as` and
`xcrun metallib` (a `packageMetallib` helper in `FrontendTool.cpp`) to produce a
loadable `.metallib` in one step:

```sh
swift-frontend -emit-metallib -O -parse-as-library kernel.swift -o kernel.metallib
```

Verified: `swift-frontend -emit-metallib` on `examples/devadd` → a MetalLib
executable that runs correctly on the GPU. **This is the `smc` replacement** —
the compiler owns the whole pipeline.

## Remaining to fully retire `smc`

- **`swiftc` driver routing**: `swiftc` uses `swift-driver` (a separate Swift
  package), not the legacy C++ driver. `-emit-air`/`-emit-metallib` work via
  `swift-frontend` directly (and the legacy C++ driver, which recognizes them);
  add the modes to `swift-driver` for `swiftc -emit-metallib`.
- **Examples**: `add`/`vscale`/`indices` use `@Binding` but not `@Device`, so on
  the native path their buffers would be `addrspace(0)`; port them to `@Device`.
