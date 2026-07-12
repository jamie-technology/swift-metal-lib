// Atomics — the second swift-metal *package*. Atomic read-modify-write on a
// `@Device` UInt32 location, layered on the `air.atomic.global.*` intrinsics.
// (MSL's `atomic_uint` is just a device i32; no wrapper type is needed.)
//
// Compile alongside a kernel that uses atomics:
//   swift-frontend -emit-metallib -O -parse-as-library \
//       packages/Atomics/Atomics.swift my_kernel.swift -o my.metallib
//
// The ordering operands are (memory_order = relaxed(0), scope = device(2),
// volatile = true) — the common relaxed-device form.

@_silgen_name("air.atomic.global.add.u.i32")
func _airAtomicAdd(@Device _ p: UnsafeMutablePointer<UInt32>, _ v: UInt32, _ o: Int32, _ s: Int32, _ x: Bool) -> UInt32
@_silgen_name("air.atomic.global.sub.u.i32")
func _airAtomicSub(@Device _ p: UnsafeMutablePointer<UInt32>, _ v: UInt32, _ o: Int32, _ s: Int32, _ x: Bool) -> UInt32
@_silgen_name("air.atomic.global.max.u.i32")
func _airAtomicMax(@Device _ p: UnsafeMutablePointer<UInt32>, _ v: UInt32, _ o: Int32, _ s: Int32, _ x: Bool) -> UInt32
@_silgen_name("air.atomic.global.min.u.i32")
func _airAtomicMin(@Device _ p: UnsafeMutablePointer<UInt32>, _ v: UInt32, _ o: Int32, _ s: Int32, _ x: Bool) -> UInt32
@_silgen_name("air.atomic.global.or.u.i32")
func _airAtomicOr(@Device _ p: UnsafeMutablePointer<UInt32>, _ v: UInt32, _ o: Int32, _ s: Int32, _ x: Bool) -> UInt32
@_silgen_name("air.atomic.global.and.u.i32")
func _airAtomicAnd(@Device _ p: UnsafeMutablePointer<UInt32>, _ v: UInt32, _ o: Int32, _ s: Int32, _ x: Bool) -> UInt32
@_silgen_name("air.atomic.global.xor.u.i32")
func _airAtomicXor(@Device _ p: UnsafeMutablePointer<UInt32>, _ v: UInt32, _ o: Int32, _ s: Int32, _ x: Bool) -> UInt32

/// Atomically add `value` to `*p`, returning the previous value.
public func atomicFetchAdd(@Device _ p: UnsafeMutablePointer<UInt32>, _ value: UInt32) -> UInt32 { _airAtomicAdd(p, value, 0, 2, true) }
/// Atomically subtract `value` from `*p`, returning the previous value.
public func atomicFetchSub(@Device _ p: UnsafeMutablePointer<UInt32>, _ value: UInt32) -> UInt32 { _airAtomicSub(p, value, 0, 2, true) }
/// Atomically set `*p = max(*p, value)`, returning the previous value.
public func atomicFetchMax(@Device _ p: UnsafeMutablePointer<UInt32>, _ value: UInt32) -> UInt32 { _airAtomicMax(p, value, 0, 2, true) }
/// Atomically set `*p = min(*p, value)`, returning the previous value.
public func atomicFetchMin(@Device _ p: UnsafeMutablePointer<UInt32>, _ value: UInt32) -> UInt32 { _airAtomicMin(p, value, 0, 2, true) }
/// Atomically set `*p |= value`, returning the previous value.
public func atomicFetchOr(@Device _ p: UnsafeMutablePointer<UInt32>, _ value: UInt32) -> UInt32 { _airAtomicOr(p, value, 0, 2, true) }
/// Atomically set `*p &= value`, returning the previous value.
public func atomicFetchAnd(@Device _ p: UnsafeMutablePointer<UInt32>, _ value: UInt32) -> UInt32 { _airAtomicAnd(p, value, 0, 2, true) }
/// Atomically set `*p ^= value`, returning the previous value.
public func atomicFetchXor(@Device _ p: UnsafeMutablePointer<UInt32>, _ value: UInt32) -> UInt32 { _airAtomicXor(p, value, 0, 2, true) }
