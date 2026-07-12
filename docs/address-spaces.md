# GPU address spaces in the swift-gpu fork

**Status: working and GPU-verified.** `@Device`/`@Constant`/`@Threadgroup`/
`@Thread` are pointer-type qualifiers the fork's `swiftc` understands; IRGen
emits `ptr addrspace(N)` **natively** (device=1, constant=2, threadgroup=3,
thread=0). No post-processing, no reliance on optimization.

```swift
@Compute @_silgen_name("devadd")
func devadd(@Binding(to: 0) @Device _ a: UnsafePointer<Float>,
            @Binding(to: 1) @Device _ b: UnsafePointer<Float>,
            @Binding(to: 2) @Device _ out: UnsafeMutablePointer<Float>,
            @ThreadPositionInGrid _ gid: UInt32) {
    out[Int(gid)] = a[Int(gid)] + b[Int(gid)]
}
```
lowers to `define void @devadd(ptr addrspace(1) …, ptr addrspace(1) …, …)` with
every GEP/load/store in `addrspace(1)`. Runs correctly on the GPU.

## The model (Clang / MSL)

The address space qualifies the **pointee**, not the pointer:
`@Device _ p: UnsafePointer<Float>` is sugar for `UnsafePointer<device Float>`.
This is the key decision — it means `p` stays an ordinary `UnsafePointer<X>`, so
subscript/`pointee` resolve with **no coercion wall**. Two rules follow:

- **A pointer to address-space-N memory is `ptr addrspace(N)`.** IRGen gives
  `UnsafePointer<device T>` a distinct concrete `TypeInfo` whose `_rawValue`
  field is `ptr addrspace(N)`.
- **The qualifier drops on load.** A `device Float` *value* in a register is just
  a `Float` (same representation) — so it participates in arithmetic and can be
  stored to any address space. But two *pointer* types with different address
  spaces stay distinct (you can't pass a `device` pointer where `constant` is
  expected).

Why not qualify the *pointer* (`device (UnsafePointer<Float>)`)? Because using it
requires coercing against `UnsafePointer`'s `self: UnsafePointer<Float>` — a
conversion that either strips the address space or needs an unprincipled cast.
Qualifying the pointee sidesteps this entirely.

## Where each rule lives (fork changes)

Representation:
- `AddressSpaceType` — a canonical AST type node wrapping a pointee type + an
  `unsigned` address space (`TypeNodes.def`, `Types.h`, `ASTContext.cpp`, plus
  the exhaustive `TypeVisitor`/switch sites — see `fork-changes.md`).
- `@Device`/`@Constant`/`@Threadgroup`/`@Thread` — `SIMPLE_DECL_ATTR`s, `OnParam
  | OnVar`. Sema wraps the *pointee* of a qualified pointer param/var
  (`TypeCheckDecl.cpp` `applyGPUAddressSpace`).

Transparency for type-checking (the qualifier is invisible to Sema *except* for
pointer identity):
- **Member/subscript lookup** looks through the qualifier (`CSSimplify.cpp`
  `performMemberLookup`).
- **`matchTypes`** looks through it for *conversions* but not invariant `Equal`
  (so generic args — `UnsafePointer<device T>` vs `UnsafePointer<constant T>` —
  stay distinct, keeping pointer address spaces from mixing).
- **`coerceToType`** treats an address-space-only value coercion as an identity.
- **Conformance** delegates to the underlying type (`device Float` is `Escapable`
  iff `Float` is) — `ConformanceLookup.cpp`.

Codegen:
- **Drop-on-load**: `getLoweredRValueType` lowers a standalone `AddressSpace(N,T)`
  to `T`, *except* on a raw pointer, where the address space IS the
  representation (`TypeLowering.cpp`).
- **Native pointer storage**: `convertType` gives an address-space-qualified
  `UnsafePointer` a distinct concrete `TypeInfo`; the `getType` field intercept
  lowers its `_rawValue` to `ptr addrspace(N)`; `pointer_to_address` preserves
  the address space (`GenType.cpp`, `GenStruct.cpp`, `IRGenSIL.cpp`).

## Known refinements (not yet done)

- Local `@Device var` bindings inside a body: the Sema wrap is currently applied
  to parameters (`DeclKind::Param`); extend to `DeclKind::Var`.
- `@Threadgroup var shared: …` as an *allocation* in addrspace(3) (storage-AS, vs
  the pointee-AS handled here) — `createAlloca` address space.
- Mangling is a Stage-1 stub (address space invisible to the mangler); fine while
  kernels use `@_silgen_name`, needs real mangling for `.swiftinterface`.
