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
