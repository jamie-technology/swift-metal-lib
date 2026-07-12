// Atomics — the second swift-metal *package*. Atomic read-modify-write on
// `@Device` memory, layered on the `air.atomic.global.*` intrinsics. (MSL's
// `atomic_uint`/`atomic_int`/`atomic_float` are just device i32/i32/f32; no
// wrapper type is needed.)
//
// Compile alongside a kernel that uses atomics:
//   swift-frontend -emit-metallib -O -parse-as-library \
//       packages/Atomics/Atomics.swift my_kernel.swift -o my.metallib
//
// The ordering operands are (memory_order = relaxed(0), scope = device(2),
// volatile = true) — the common relaxed-device form.

// MARK: - UInt32 (unsigned)

@_silgen_name("air.atomic.global.add.u.i32")
func _aAddU(@Device _ p: UnsafeMutablePointer<UInt32>, _ v: UInt32, _ o: Int32, _ s: Int32, _ x: Bool) -> UInt32
@_silgen_name("air.atomic.global.sub.u.i32")
func _aSubU(@Device _ p: UnsafeMutablePointer<UInt32>, _ v: UInt32, _ o: Int32, _ s: Int32, _ x: Bool) -> UInt32
@_silgen_name("air.atomic.global.max.u.i32")
func _aMaxU(@Device _ p: UnsafeMutablePointer<UInt32>, _ v: UInt32, _ o: Int32, _ s: Int32, _ x: Bool) -> UInt32
@_silgen_name("air.atomic.global.min.u.i32")
func _aMinU(@Device _ p: UnsafeMutablePointer<UInt32>, _ v: UInt32, _ o: Int32, _ s: Int32, _ x: Bool) -> UInt32
@_silgen_name("air.atomic.global.or.u.i32")
func _aOrU(@Device _ p: UnsafeMutablePointer<UInt32>, _ v: UInt32, _ o: Int32, _ s: Int32, _ x: Bool) -> UInt32
@_silgen_name("air.atomic.global.and.u.i32")
func _aAndU(@Device _ p: UnsafeMutablePointer<UInt32>, _ v: UInt32, _ o: Int32, _ s: Int32, _ x: Bool) -> UInt32
@_silgen_name("air.atomic.global.xor.u.i32")
func _aXorU(@Device _ p: UnsafeMutablePointer<UInt32>, _ v: UInt32, _ o: Int32, _ s: Int32, _ x: Bool) -> UInt32

public func atomicFetchAdd(@Device _ p: UnsafeMutablePointer<UInt32>, _ v: UInt32) -> UInt32 { _aAddU(p, v, 0, 2, true) }
public func atomicFetchSub(@Device _ p: UnsafeMutablePointer<UInt32>, _ v: UInt32) -> UInt32 { _aSubU(p, v, 0, 2, true) }
public func atomicFetchMax(@Device _ p: UnsafeMutablePointer<UInt32>, _ v: UInt32) -> UInt32 { _aMaxU(p, v, 0, 2, true) }
public func atomicFetchMin(@Device _ p: UnsafeMutablePointer<UInt32>, _ v: UInt32) -> UInt32 { _aMinU(p, v, 0, 2, true) }
public func atomicFetchOr(@Device _ p: UnsafeMutablePointer<UInt32>, _ v: UInt32) -> UInt32 { _aOrU(p, v, 0, 2, true) }
public func atomicFetchAnd(@Device _ p: UnsafeMutablePointer<UInt32>, _ v: UInt32) -> UInt32 { _aAndU(p, v, 0, 2, true) }
public func atomicFetchXor(@Device _ p: UnsafeMutablePointer<UInt32>, _ v: UInt32) -> UInt32 { _aXorU(p, v, 0, 2, true) }

// MARK: - Int32 (signed)

@_silgen_name("air.atomic.global.add.s.i32")
func _aAddS(@Device _ p: UnsafeMutablePointer<Int32>, _ v: Int32, _ o: Int32, _ s: Int32, _ x: Bool) -> Int32
@_silgen_name("air.atomic.global.sub.s.i32")
func _aSubS(@Device _ p: UnsafeMutablePointer<Int32>, _ v: Int32, _ o: Int32, _ s: Int32, _ x: Bool) -> Int32
@_silgen_name("air.atomic.global.max.s.i32")
func _aMaxS(@Device _ p: UnsafeMutablePointer<Int32>, _ v: Int32, _ o: Int32, _ s: Int32, _ x: Bool) -> Int32
@_silgen_name("air.atomic.global.min.s.i32")
func _aMinS(@Device _ p: UnsafeMutablePointer<Int32>, _ v: Int32, _ o: Int32, _ s: Int32, _ x: Bool) -> Int32
@_silgen_name("air.atomic.global.or.s.i32")
func _aOrS(@Device _ p: UnsafeMutablePointer<Int32>, _ v: Int32, _ o: Int32, _ s: Int32, _ x: Bool) -> Int32
@_silgen_name("air.atomic.global.and.s.i32")
func _aAndS(@Device _ p: UnsafeMutablePointer<Int32>, _ v: Int32, _ o: Int32, _ s: Int32, _ x: Bool) -> Int32
@_silgen_name("air.atomic.global.xor.s.i32")
func _aXorS(@Device _ p: UnsafeMutablePointer<Int32>, _ v: Int32, _ o: Int32, _ s: Int32, _ x: Bool) -> Int32

public func atomicFetchAdd(@Device _ p: UnsafeMutablePointer<Int32>, _ v: Int32) -> Int32 { _aAddS(p, v, 0, 2, true) }
public func atomicFetchSub(@Device _ p: UnsafeMutablePointer<Int32>, _ v: Int32) -> Int32 { _aSubS(p, v, 0, 2, true) }
public func atomicFetchMax(@Device _ p: UnsafeMutablePointer<Int32>, _ v: Int32) -> Int32 { _aMaxS(p, v, 0, 2, true) }
public func atomicFetchMin(@Device _ p: UnsafeMutablePointer<Int32>, _ v: Int32) -> Int32 { _aMinS(p, v, 0, 2, true) }
public func atomicFetchOr(@Device _ p: UnsafeMutablePointer<Int32>, _ v: Int32) -> Int32 { _aOrS(p, v, 0, 2, true) }
public func atomicFetchAnd(@Device _ p: UnsafeMutablePointer<Int32>, _ v: Int32) -> Int32 { _aAndS(p, v, 0, 2, true) }
public func atomicFetchXor(@Device _ p: UnsafeMutablePointer<Int32>, _ v: Int32) -> Int32 { _aXorS(p, v, 0, 2, true) }

// MARK: - Float

@_silgen_name("air.atomic.global.add.f32")
func _aAddF(@Device _ p: UnsafeMutablePointer<Float>, _ v: Float, _ o: Int32, _ s: Int32, _ x: Bool) -> Float

/// Atomically add `value` to `*p`, returning the previous value.
public func atomicFetchAdd(@Device _ p: UnsafeMutablePointer<Float>, _ v: Float) -> Float { _aAddF(p, v, 0, 2, true) }

// MARK: - Load & store (UInt32)

@_silgen_name("air.atomic.global.load.i32")
func _aLoad(@Device _ p: UnsafeMutablePointer<UInt32>, _ o: Int32, _ s: Int32, _ x: Bool) -> UInt32
@_silgen_name("air.atomic.global.store.i32")
func _aStore(@Device _ p: UnsafeMutablePointer<UInt32>, _ v: UInt32, _ o: Int32, _ s: Int32, _ x: Bool)

/// Atomically load `*p`.
public func atomicLoad(@Device _ p: UnsafeMutablePointer<UInt32>) -> UInt32 { _aLoad(p, 0, 2, true) }
/// Atomically store `value` into `*p`.
public func atomicStore(@Device _ p: UnsafeMutablePointer<UInt32>, _ value: UInt32) { _aStore(p, value, 0, 2, true) }

// MARK: - Exchange & compare-exchange (UInt32)

@_silgen_name("air.atomic.global.xchg.i32")
func _aXchg(@Device _ p: UnsafeMutablePointer<UInt32>, _ v: UInt32, _ o: Int32, _ s: Int32, _ x: Bool) -> UInt32
@_silgen_name("air.atomic.global.cmpxchg.weak.i32")
func _aCmpxchg(@Device _ p: UnsafeMutablePointer<UInt32>, _ expected: UnsafeMutablePointer<UInt32>,
               _ desired: UInt32, _ os: Int32, _ of: Int32, _ s: Int32, _ x: Bool) -> UInt32

/// Atomically store `value` into `*p`, returning the previous value.
public func atomicExchange(@Device _ p: UnsafeMutablePointer<UInt32>, _ value: UInt32) -> UInt32 {
    _aXchg(p, value, 0, 2, true)
}

/// Atomically: if `*p == expected`, store `desired` and return true; otherwise
/// load `*p` into `expected` and return false (weak — may fail spuriously).
public func atomicCompareExchange(@Device _ p: UnsafeMutablePointer<UInt32>,
                                  _ expected: inout UInt32, _ desired: UInt32) -> Bool {
    // The intrinsic returns the *old* value; the exchange happened iff that
    // equals what we expected. Update `expected` to the observed value so a
    // caller's CAS loop retries against the current contents.
    let want = expected
    let old = _aCmpxchg(p, &expected, desired, 0, 0, 2, true)
    expected = old
    return old == want
}
