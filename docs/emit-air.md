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

Address spaces are **not** rewritten here — IRGen already emits them natively
(see `docs/address-spaces.md`). That's why the pass is small.

## Remaining to fully retire `smc`

- **Driver routing**: `swiftc -emit-air` isn't recognized by the driver yet
  (only `swift-frontend`); add driver handling.
- **`-emit-metallib`**: a mode that invokes `xcrun metal-as`/`metallib` from the
  frontend (see the exploration in `docs/fork-changes.md`), producing a
  `.metallib` in one step.
- **Examples**: `add`/`vscale`/`indices` use `@Binding` but not `@Device`, so on
  the native path their buffers would be `addrspace(0)`; port them to `@Device`.
