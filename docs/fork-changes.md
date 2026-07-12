# swift-gpu fork changes

The `smc` pipeline depends on a GPU-capable `swiftc`: a fork of the Swift
compiler that understands GPU attributes and emits `!swiftgpu.kernels` metadata.
This documents the patches applied to `~/Developer/swift-gpu-fork/swift`.

The fork tree is **not** under version control, so every edited file has a
`<file>.smc-bak` sibling holding its pre-patch contents. To revert:
`for f in $(find . -name '*.smc-bak'); do cp "$f" "${f%.smc-bak}"; done`.

## What was added

Three GPU attributes plus one IRGen metadata pass.

- `@Compute` — `SIMPLE_DECL_ATTR`, `OnFunc`. Marks a compute kernel entry point.
- `@ThreadPositionInGrid` and 5 siblings (`@ThreadPositionInThreadgroup`,
  `@ThreadgroupPositionInGrid`, `@ThreadIndexInThreadgroup`,
  `@ThreadsPerThreadgroup`, `@ThreadgroupsPerGrid`) — `SIMPLE_DECL_ATTR`, `OnParam`.
- `@Binding(to: N)` — full `DECL_ATTR` carrying an integer slot, `OnParam`
  (modeled on `@_alignment`).
- `IRGenModule::emitSwiftGPUKernelMetadata()` — after all SIL functions are
  emitted, walks `@Compute` functions and emits one `!swiftgpu.kernels` node per
  kernel:

  ```llvm
  !swiftgpu.kernels = !{!16}
  !16 = !{ptr @add, !"compute", !17}
  !17 = !{!18, !19, !20, !21}
  !18 = !{i32 0, !"buffer", i32 0, !"UnsafePointer<Float>", !"a"}     ; astIdx, role, slot, swiftType, name
  !21 = !{i32 3, !"threadPositionInGrid", i32 -1, !"UInt32", !"gid"}
  ```

## Files touched (attribute codes 177–184)

| File | Change |
| --- | --- |
| `include/swift/AST/DeclAttr.def` | the 8 attribute definitions; bump `LAST_DECL_ATTR` |
| `include/swift/AST/Attr.h` | `BindingAttr` class + bitfield (template: `AlignmentAttr`) |
| `include/swift/AST/DiagnosticsParse.def` | `binding_index_must_be_integer` diagnostic |
| `lib/Parse/ParseDecl.cpp` | `@Binding(to: N)` parser case (parses the `to:` label) |
| `lib/Sema/TypeCheckAttr.cpp` | `IGNORED_ATTR(...)` for all 8 (no-op checks) |
| `lib/Sema/TypeCheckDeclOverride.cpp` | `UNINTERESTING_ATTR(...)` for all 8 |
| `lib/AST/ASTDumper.cpp` | `TRIVIAL_ATTR_PRINTER` (simple) + `visitBindingAttr` |
| `lib/AST/Attr.cpp` | `Binding` print case + `getAttrName()` case |
| `lib/Serialization/ModuleFormat.h` | `BindingDeclAttrLayout` |
| `lib/Serialization/Serialization.cpp` | `Binding` write case |
| `lib/Serialization/Deserialization.cpp` | `Binding` read case |
| `lib/ASTGen/Sources/ASTGen/DeclAttrs.swift` | simple attrs in the case list; `Binding` stubbed (C++ parser handles it; ASTGen isn't the default frontend parser) |
| `lib/IRGen/IRGenModule.{h,cpp}` | `emitSwiftGPUKernelMetadata()` + call in `finalize()` |

Value-generic operators on address-space-qualified values (e.g. `device
SIMD4<Float> * 2.0`) — the qualifier is transparent to the generics machinery,
resolved against the unqualified object type at three points (see
`docs/address-spaces.md`):

| File | Change |
| --- | --- |
| `lib/Sema/ConstraintSystem.cpp` | `simplifyType` dependent-member case: `device SIMD4<Float>.Scalar` → `Float` (lets the operator type-check) |
| `lib/AST/TypeSubstitution.cpp` | `getContextSubstitutions`: strip the qualifier from the member's base type (else SILGen asserts *"Bad base type"*) |
| `include/swift/SIL/SILCloner.h` | `visitWitnessMethodInst`: un-qualify the cloned `witness_method` lookup type so it matches its concrete conformance during inlining |
| `lib/SILGen/SILGenApply.cpp` | un-qualify a `witness_method`'s lookup type at creation, so a protocol operator on a device value (`FixedWidthInteger.&*` with `Self = device UInt32`) matches its concrete conformance |
| `lib/AST/ASTVerifier.cpp` | `equalIgnoringAddressSpace`: the ApplyExpr-result and assignment-operand consistency checks treat `device T` and `T` as equal (they lower identically) — lets device-loaded scalars flow through generic operators and store into device locations |

Threadgroup shared memory (`examples/reduce`) — all in `lib/IRGen/IRGen.cpp`:

| Change | Detail |
| --- | --- |
| Threadgroup buffer index | threadgroup (addrspace 3) buffer args are numbered in their own 0-based `[[threadgroup(N)]]` namespace, separate from `[[buffer(N)]]` |
| `convergent` intrinsics | `air.*` intrinsic declarations (e.g. `air.wg.barrier`, declared via `@_silgen_name`) and their call sites are marked `convergent` (+ clean attributes) — required for barriers |
| No auto-vectorization | the GPU pipeline sets `PTO.{Loop,SLP}Vectorization = false`: the host vectorizer's `<N x T>` loads and `llvm.vector.reduce.*` intrinsics crash the AIR back-end (source-level SIMD types are unaffected) |

Textures (`examples/texture`, `packages/Textures`):

| File | Change |
| --- | --- |
| `lib/IRGen/IRGenModule.cpp` | a param whose nominal type is `Texture2D`/`WriteTexture2D` gets a `textureRead`/`textureWrite` role in `!swiftgpu.kernels` |
| `lib/IRGen/IRGen.cpp` | normalize pass emits `air.texture` (read/write) in the `[[texture(N)]]` namespace; strips Swift runtime metadata (`$s…`/`__swift…`/`swift_…` symbols — kept if a GPU data global in addrspace 1/2/3) |
| `lib/Frontend/CompilerInvocation.cpp` | GPU path disables reflection metadata (`ReflectionMetadataMode::None`) — user types (Texture2D) otherwise emit `__swift5_*` records metal-as can't parse |
| `lib/FrontendTool/FrontendTool.cpp` | the typed-pointer rewrite is gated on a constant-address-space global — texture/device kernels stay fully opaque (which the driver accepts; typing is all-or-nothing) |

The texture type itself needs no dedicated IRGen: `Texture2D<T>` wraps one
`@Device` pointer field, so it flattens to `ptr addrspace(1)` through the
existing address-space path.

Atomics (`examples/histogram`, `packages/Atomics`):

| File | Change |
| --- | --- |
| `lib/IRGen/IRGenSIL.cpp` | `visitAddressToPointerInst` preserves the address space (device pointer arithmetic / `&buf[i]` for atomics — mirrors the `pointer_to_address` fix) |
| `lib/IRGen/IRGen.cpp` | normalize pass strips newer `nneg` (zext) / `disjoint` (or) instruction flags metal-as can't parse |

The atomic ops reuse everything else (`@Device` pointers, `air.*` convergent
calls, opaque pointers) — no atomic type needed (`atomic_uint` is a device i32).

Constant global data — a program-scope `let table: InlineArray<N,Float> = [...]`
placed in the constant address space (see `docs/address-spaces.md`):

| File | Change |
| --- | --- |
| `lib/IRGen/GenDecl.{h,cpp}` | `createVariable` gained an `addressSpace` param; `getAddrOfSILGlobalVariable` emits a static-initialized global into addrspace 2 in GPU mode and preserves that space through the constant bitcast |
| `lib/IRGen/IRGenSIL.cpp` | `visitGlobalAddrInst` preserves the global's address space instead of casting to the default `ptr addrspace(0)` |
| `lib/IRGen/IRGen.cpp` | normalize pass strips the `"PIC Level"` module flag (crashes the driver on addrspace-2 globals) |

Typed (non-opaque) pointers — the printed AIR is rewritten to typed pointers,
which the driver back-end requires:

| File | Change |
| --- | --- |
| `lib/FrontendTool/FrontendTool.cpp` | `rewriteAIRToTypedPointers` (textual): flatten Swift wrapper structs to MSL leaves + reconstruct typed pointers from `load`/`store`/`gep` element types; applied in place after `performLLVM`, before `metal-as` |

Adding a decl attribute is exhaustive-visitor-heavy: `TypeCheckAttr.cpp`,
`TypeCheckDeclOverride.cpp`, and `ASTDumper.cpp` each delete the default
`visitDeclAttribute`, so every new attr needs an entry in all three.

## Rebuild

```sh
ninja -C ~/Developer/swift-gpu-fork/build/Ninja-RelWithDebInfoAssert+swift-DebugAssert/swift-macosx-arm64 swift-frontend
```

The first build after editing `Attr.h`/`DeclAttr.def` recompiles most of the
front end (~10–30 min); later `.cpp`-only edits (e.g. iterating on IRGen) relink
in a couple of minutes.

## Known gaps / follow-ups

- **ASTGen**: `@Binding` is stubbed in the swift-syntax parser (`return handle(nil)`).
  Fine while the C++ parser is the default frontend path; needs a real
  `BridgedBindingAttr` bridge before ASTGen becomes default.
- **Symbol naming**: kernels still use `@_silgen_name("…")` for a clean AIR
  symbol. A future `@Compute` could imply an unmangled external name.
- **Address spaces** are still applied by the post-processing pass, not IRGen.
