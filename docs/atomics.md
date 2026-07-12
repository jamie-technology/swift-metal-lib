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

Unlike textures, atomics need **no special type**: MSL's `atomic_uint` is just a
device `i32`, and `air.atomic.global.add.u.i32` takes a plain `i32 addrspace(1)*`.
So the atomic buffer is an ordinary `@Device UnsafeMutablePointer<UInt32>`, and
the package provides free functions:

```swift
atomicFetchAdd/Sub/Max/Min/Or/And/Xor(_ p: UnsafeMutablePointer<UInt32>, _ v: UInt32) -> UInt32
```

each wrapping the intrinsic with the relaxed-device ordering operands
(`memory_order relaxed = 0`, `scope device = 2`, `volatile = true`).

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

## Not yet

- Only `UInt32` (`.u.i32`). `Int32` (`.s.i32`), `atomic_float` add, `exchange`,
  `compare_exchange`, threadgroup-scoped atomics (`air.atomic.local.*`), and a
  typed `Atomic<T>` wrapper.
