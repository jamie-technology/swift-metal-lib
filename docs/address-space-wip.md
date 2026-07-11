# Address-space-aware pointer types — WIP notes

Status: **IRGen mechanism proven; AST `AddressSpaceType` node drafted; not yet wired.**
The fork's installed `swift-frontend` is the last good build (examples pass); the
node source was reverted after capturing it here so the tree stays buildable.

## Proven (keep)

Two IRGen changes make IRGen emit native `ptr addrspace(N)` params **and** body
(GEP/load/store), GPU-validated, no casts/crash:

1. `TypeConverter::getRawPointerTypeInfo` (`lib/IRGen/GenType.cpp` ~1844): build
   `RawPointerTypeInfo` with `llvm::PointerType::get(ctx, N)` storage instead of
   `IGM.Int8PtrTy`. (For the real feature: a per-address-space cache/overload.)
2. `IRGenSILFunction::visitPointerToAddressInst` (`lib/IRGen/IRGenSIL.cpp` ~7431):
   **do not** force `IGM.PtrTy`; preserve the incoming pointer's address space:
   ```cpp
   unsigned as = cast<llvm::PointerType>(ptrValue->getType())->getAddressSpace();
   ptrValue = Builder.CreateBitCast(ptrValue, llvm::PointerType::get(ctx, as));
   ```
   (This one is universally correct — kept in the tree.)

Validated by temporarily forcing `getRawPointerTypeInfo` to AS1 globally: the
`add` kernel emitted native `addrspace(1)` throughout and ran correctly on GPU.

## The `AddressSpaceType` AST node (drafted, reverted)

A structural `TYPE(AddressSpace, Type)` wrapping a pointer object type + an
`unsigned` address space, uniqued on `(Type, unsigned)`. Modeled exactly on
`LValueType`. Edits made (and reverted) — this is the recipe to re-apply:

- `include/swift/AST/TypeNodes.def`: `TYPE(AddressSpace, Type)` after `InOut`.
- `include/swift/AST/Types.h`: `class AddressSpaceType : public TypeBase` with
  `Type ObjectTy; unsigned TheAddressSpace;`, `get(Type, unsigned)`,
  `getObjectType()`, `getAddressSpace()`, `classof`, and a `CAN_TYPE_WRAPPER`.
- `lib/AST/ASTContext.cpp`: `DenseMap<std::pair<Type,unsigned>, AddressSpaceType*>`
  in the Arena, and `AddressSpaceType::get` (copy `LValueType::get`, key on the
  pair, canonical iff object is canonical).
- Switch/visitor sites that need an `AddressSpace` case (found by build, small):
  `lib/AST/Type.cpp` `computeCanonicalType`; `include/swift/AST/TypeTransform.h`
  (transform object, rebuild); `lib/AST/ASTMangler.cpp` `appendType` (Stage-1
  stub: mangle transparently as the object — collision caveat below);
  `lib/AST/ASTPrinter.cpp` + `lib/AST/ASTDumper.cpp` (`visitAddressSpaceType`);
  `lib/AST/ExistentialGeneralization.cpp` `Generalizer` and any other
  `TypeVisitor` subclass lacking a `visitType` fallback (~a handful, one per
  build); `lib/IRGen/GenType.cpp` `convertType` (return an AS-N
  `getRawPointerTypeInfo`); SIL `TypeClassifierBase` in
  `lib/SIL/IR/TypeLowering.cpp` (classify like the object pointer).

Total ~17 `TypeVisitor` subclasses exist; nearly all have a `visitType`
fallback, so only a few error — this is NOT dozens of sites.

## The crux problem (the real remaining design work)

`@Device _ p: UnsafePointer<Float>` gives `p` the type
`AddressSpaceType(1, UnsafePointer<Float>)`. But `UnsafePointer` is a struct
`{ let _rawValue: Builtin.RawPointer }`, and the body does
`pointer_to_address(struct_extract(p, _rawValue))`. `struct_extract` yields
`_rawValue` at its **declared** type `Builtin.RawPointer` (address space 0), so
the address space on the outer struct is lost before the load. The pointer that
actually feeds GEP/load/store must be AS-N.

Options to solve (pick one, then Stage 1 works end-to-end):
1. **AS distribution through aggregates**: a field extracted from an
   AS-qualified aggregate is itself AS-qualified. Cleanest semantically; touches
   SIL type computation for `struct_extract` (and friends).
2. **IRGen-level**: in `visitStructExtractInst`, if the operand type is
   `AddressSpaceType`, produce an AS-N raw pointer. Must keep the SIL result
   type and the lowered LLVM value consistent (Explosion type) — fiddly.
3. **Qualify at the leaf**: represent `@Device UnsafePointer<Float>` so the inner
   `RawPointer` carries the AS directly (e.g. Sema lowers to a form whose
   `_rawValue` field type is `AddressSpaceType(1, RawPointer)`), avoiding the
   struct barrier. Likely the most faithful to "AS is on the pointer."

## Remaining stages once the crux is chosen

1. `@Device`/`@Constant`/`@Threadgroup`/`@Thread` decl attrs (routine recipe:
   `docs/fork-changes.md`) — OnParam + OnVar.
2. Sema: resolving a param/var with the attr wraps its (pointer) type in
   `AddressSpaceType(N)`. Keep AS0↔ASN from silently crossing call boundaries.
3. IRGen: the two proven changes, keyed off the qualified type (per-AS cache).
4. Wire `@Compute` kernels onto this; delete `smc`'s address-space rewrite; then
   `swiftc -emit-air`/`-emit-metallib` (device triple selector).

## Mangling caveat

Stage-1 stub mangles `AddressSpaceType` transparently as its object (no new
demangler grammar). Two decls differing only by address space would mangle
identically; kernels use `@_silgen_name` so entry-point symbols are unaffected.
Real mangling is a later stage.
