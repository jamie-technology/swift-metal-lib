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

Value-generic operators on qualified values (e.g. `device SIMD4<Float> * 2.0`,
where the SIMD operator is a protocol-extension method dispatched with
`Self = device SIMD4<Float>`): the qualifier describes *storage*, not the value,
so it is transparent to the generics machinery at three more points, each
resolving against the unqualified object type:
- **Associated-type resolution** — `device SIMD4<Float>.Scalar` is `Float`
  (`ConstraintSystem.cpp`, `simplifyType`'s dependent-member case). This is what
  lets the operator type-check.
- **Member substitution** — a member whose `Self`/base substitutes to a qualified
  value is substituted against the unqualified type (`TypeSubstitution.cpp`,
  `getContextSubstitutions`). Without this SILGen asserts *"Bad base type."*
- **Witness-method lookup during inlining** — when a protocol-extension method is
  inlined with a qualified `Self`, the cloned `witness_method`'s lookup type is
  un-qualified to match its concrete conformance (`SILCloner.h`,
  `visitWitnessMethodInst`).

Scalar arithmetic (`device Float + device Float`) needs none of these: `Float`'s
operators are concrete, so there is no generic `Self` to dispatch. Only the
generic protocol path (SIMD/vector) exercises the points above.

Codegen:
- **Drop-on-load**: `getLoweredRValueType` lowers a standalone `AddressSpace(N,T)`
  to `T`, *except* on a raw pointer, where the address space IS the
  representation (`TypeLowering.cpp`).
- **Native pointer storage**: `convertType` gives an address-space-qualified
  `UnsafePointer` a distinct concrete `TypeInfo`; the `getType` field intercept
  lowers its `_rawValue` to `ptr addrspace(N)`; `pointer_to_address` preserves
  the address space (`GenType.cpp`, `GenStruct.cpp`, `IRGenSIL.cpp`).

## Constant global data (program-scope constants)

A program-scope constant with static initializer data — e.g. a lookup table
`let gain: InlineArray<8, Float> = [...]` (`InlineArray` is a fixed-size *value*
type, so no heap) — is placed in the MSL **constant** address space (AIR
addrspace 2). This is the only legal address space for program-scope read-only
data in MSL, and the driver only bakes the bytes into the metallib when the
global lives there. See `examples/constdata`.

- **Placement**: `getAddrOfSILGlobalVariable` emits a global with a static
  initializer (`var->getStaticInitializerValue()`) into addrspace 2 when in GPU
  mode; `createVariable` gained an `addressSpace` parameter (`GenDecl.cpp`). The
  GEP/loads rooted at the global inherit the address space, so no reference
  rewrite is needed. `global_addr` lowering and the constant bitcast preserve
  the non-default address space instead of forcing `ptr addrspace(0)`
  (`IRGenSIL.cpp`, `GenDecl.cpp`).
- **`PIC Level`**: the normalization pass strips the `"PIC Level"` module flag
  (`IRGen.cpp`). Position-independent code is meaningless for a shader, and it
  makes the driver's back-end compiler **crash** on an addrspace-2 constant
  global. (Device-only kernels tolerate it — they have no global data — which is
  why this only surfaced with constant globals.)

## Known refinements (not yet done)

- **Device *scalar* values in non-uniform expressions.** A value loaded from a
  device pointer is typed `device T`. When the whole expression is device-uniform
  (`out[i] = a[i] + b[i]`, or SIMD arithmetic on a loaded vector) it works. But
  mixing a device scalar with a non-device value in a *generic* operator/
  initializer — `Int(dims[i])`, `gid.y &* width` where `width = dims[0]` — or
  storing a *computed non-device* value into a device location — `out[i] =
  UInt32(x)` — trips the AST verifier (`result of ApplyExpr does not match … device
  T vs T`). The clean fix is drop-on-load *during solving* (a pointee read yields
  the unqualified value), which the current pointee-qualification model can't do
  cleanly (the subscript's `Pointee` type variable is shared between the pointer's
  storage, which needs the qualifier, and the loaded value, which drops it).
  Workaround: keep the stored value device-uniform (`examples/grid2d` transposes
  device floats and computes indices in plain `Int`).
- Local `@Device var` bindings inside a body: the Sema wrap is currently applied
  to parameters (`DeclKind::Param`); extend to `DeclKind::Var`.
- `@Threadgroup var shared: …` as an *allocation* in addrspace(3) (storage-AS, vs
  the pointee-AS handled here) — `createAlloca` address space.
- Mangling is a Stage-1 stub (address space invisible to the mangler); fine while
  kernels use `@_silgen_name`, needs real mangling for `.swiftinterface`.
