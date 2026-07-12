# Atomics (the second package)

Atomic read-modify-write operations on `@Device` memory, delivered as a package
(`packages/Atomics/Atomics.swift`) over the `air.atomic.global.*` intrinsics.

## Status: working end-to-end

`examples/histogram` — 1,048,576 threads atomically increment 16 shared bins;
each bin ends at exactly 65,536 (GPU-verified). Kernel authored in Swift.

```swift
@Compute @_silgen_name("histogram")
public func histogram(@Binding(to: 0) @Device _ data: UnsafePointer<UInt32>,
                      @Binding(to: 1) @Device _ bins: UnsafeMutablePointer<UInt32>,
                      @ThreadPositionInGrid _ gid: UInt32) {
    let bin = Int(data[Int(gid)] % 16)
    _ = atomicFetchAdd(bins + bin, 1)
}
```

## Design

Unlike textures, atomics need **no special type**: MSL's `atomic_uint`/
`atomic_int`/`atomic_float` are just device `i32`/`i32`/`f32`, and e.g.
`air.atomic.global.add.u.i32` takes a plain `i32 addrspace(1)*`. So the atomic
buffer is an ordinary `@Device UnsafeMutablePointer<T>`, and the package provides
free functions (all with relaxed-device ordering — `memory_order relaxed = 0`,
`scope device = 2`, `volatile = true`):

```swift
// UInt32 (.u.i32) and Int32 (.s.i32):
atomicFetchAdd/Sub/Max/Min/Or/And/Xor(_ p: UnsafeMutablePointer<UInt32|Int32>, _ v) -> old
// Float (.add.f32):
atomicFetchAdd(_ p: UnsafeMutablePointer<Float>, _ v: Float) -> Float
// UInt32:
atomicLoad(_ p) -> UInt32 ; atomicStore(_ p, _ v) ; atomicExchange(_ p, _ v) -> old
atomicCompareExchange(_ p, _ expected: inout UInt32, _ desired) -> Bool   // weak
```

`atomicCompareExchange` maps to `air.atomic.global.cmpxchg.weak.i32`, which
returns the *old* value (success = old == expected) and updates `expected` for a
retry loop. `examples/atomics` verifies min/max/float-sum plus a CAS-loop counter
that lands at exactly the thread count under full contention.

## Compiler support (fork)

Only one fork change was needed — the intrinsics and metadata reuse existing
machinery (`@Device` pointers → `ptr addrspace(1)`, `air.*` calls marked
`convergent`, opaque pointers). Addressing a specific bin (`bins + bin`, i.e.
`&bins[bin]`) exercises SIL `address_to_pointer` on a device address:

- **`IRGenSIL.cpp` `visitAddressToPointerInst`** now preserves the pointer's
  address space instead of bitcasting to the default `Int8PtrTy` (an invalid
  cross-address-space cast) — mirroring the `pointer_to_address` fix. This lets
  device pointer arithmetic / `&buf[i]` work.
- The normalize pass also strips the newer `nneg` (zext) / `disjoint` (or) flags
  that the index math emits and metal-as (~LLVM 17) can't parse.

## Gotcha

Compare-exchange needs an addressable local (the expected-value slot), and Swift
adds `sspreq` (stack-protector-required) to any function with one. Stack
protection is meaningless on the GPU and **crashes the driver back-end** — the
normalize pass strips `ssp*` attributes. (Single-pointer atomics have no local,
so they never hit it — which is why cmpxchg was the only op that crashed.)

## Not yet

- Threadgroup-scoped atomics (`air.atomic.local.*`), `Int32`/`Float`
  exchange/cmpxchg (only `UInt32` so far), and a typed `Atomic<T>` wrapper.
