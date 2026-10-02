// SIMDGroup — the third swift-metal *package*. SIMD-group (a.k.a. subgroup /
// warp / quad) collective operations, layered on the `air.simd_*` intrinsics.
// A SIMD-group is the set of threads (32 lanes on Apple GPUs) that execute in
// lockstep on one execution unit; these ops let them cooperate directly —
// reductions, scans, shuffles — with no threadgroup memory and no barrier.
//
// Compile alongside a kernel that uses them:
//   swift-frontend -emit-metallib -O -parse-as-library \
//       packages/SIMDGroup/SIMDGroup.swift my_kernel.swift -o my.metallib
//
// Grammar (see metal-air-documentation 04-simd-group-operations): the symbol is
// air.simd_<op>[.<sign>].<type>. The sign tag (.s/.u) appears on the integer
// reductions; float ops are just .f32. Lane/mask arguments are i16 (UInt16).

// MARK: - Float reductions (every lane receives the group-wide result)

@_silgen_name("air.simd_sum.f32")
func _simdSumF(_ v: Float) -> Float
@_silgen_name("air.simd_product.f32")
func _simdProductF(_ v: Float) -> Float
@_silgen_name("air.simd_min.f32")
func _simdMinF(_ v: Float) -> Float
@_silgen_name("air.simd_max.f32")
func _simdMaxF(_ v: Float) -> Float

/// Sum of `v` across all active lanes of the SIMD-group.
public func simdSum(_ v: Float) -> Float { _simdSumF(v) }
/// Product of `v` across all active lanes.
public func simdProduct(_ v: Float) -> Float { _simdProductF(v) }
/// Minimum of `v` across all active lanes.
public func simdMin(_ v: Float) -> Float { _simdMinF(v) }
/// Maximum of `v` across all active lanes.
public func simdMax(_ v: Float) -> Float { _simdMaxF(v) }

// MARK: - Float scans (prefix reductions)

@_silgen_name("air.simd_prefix_exclusive_sum.f32")
func _simdPrefixExclusiveSumF(_ v: Float) -> Float
@_silgen_name("air.simd_prefix_inclusive_sum.f32")
func _simdPrefixInclusiveSumF(_ v: Float) -> Float

/// Exclusive prefix sum: lane `i` receives the sum of lanes `0..<i`.
public func simdPrefixExclusiveSum(_ v: Float) -> Float { _simdPrefixExclusiveSumF(v) }
/// Inclusive prefix sum: lane `i` receives the sum of lanes `0...i`.
public func simdPrefixInclusiveSum(_ v: Float) -> Float { _simdPrefixInclusiveSumF(v) }

// MARK: - Float shuffles / broadcasts (lane indices are UInt16)

@_silgen_name("air.simd_broadcast.f32")
func _simdBroadcastF(_ v: Float, _ lane: UInt16) -> Float
@_silgen_name("air.simd_broadcast_first.f32")
func _simdBroadcastFirstF(_ v: Float) -> Float
@_silgen_name("air.simd_shuffle.f32")
func _simdShuffleF(_ v: Float, _ lane: UInt16) -> Float
@_silgen_name("air.simd_shuffle_xor.f32")
func _simdShuffleXorF(_ v: Float, _ mask: UInt16) -> Float
@_silgen_name("air.simd_shuffle_up.f32")
func _simdShuffleUpF(_ v: Float, _ delta: UInt16) -> Float
@_silgen_name("air.simd_shuffle_down.f32")
func _simdShuffleDownF(_ v: Float, _ delta: UInt16) -> Float

/// The value of `v` on `lane`, read by every lane.
public func simdBroadcast(_ v: Float, from lane: UInt16) -> Float { _simdBroadcastF(v, lane) }
/// The value of `v` on the lowest active lane.
public func simdBroadcastFirst(_ v: Float) -> Float { _simdBroadcastFirstF(v) }
/// The value of `v` on `lane`.
public func simdShuffle(_ v: Float, _ lane: UInt16) -> Float { _simdShuffleF(v, lane) }
/// The value of `v` on lane `currentLane ^ mask` (butterfly exchange).
public func simdShuffleXor(_ v: Float, _ mask: UInt16) -> Float { _simdShuffleXorF(v, mask) }
/// The value of `v` on lane `currentLane - delta`.
public func simdShuffleUp(_ v: Float, _ delta: UInt16) -> Float { _simdShuffleUpF(v, delta) }
/// The value of `v` on lane `currentLane + delta`.
public func simdShuffleDown(_ v: Float, _ delta: UInt16) -> Float { _simdShuffleDownF(v, delta) }

// MARK: - Int32 reductions (signed: .s tag)

@_silgen_name("air.simd_sum.s.i32")
func _simdSumS(_ v: Int32) -> Int32
@_silgen_name("air.simd_product.s.i32")
func _simdProductS(_ v: Int32) -> Int32
@_silgen_name("air.simd_min.s.i32")
func _simdMinS(_ v: Int32) -> Int32
@_silgen_name("air.simd_max.s.i32")
func _simdMaxS(_ v: Int32) -> Int32

public func simdSum(_ v: Int32) -> Int32 { _simdSumS(v) }
public func simdProduct(_ v: Int32) -> Int32 { _simdProductS(v) }
public func simdMin(_ v: Int32) -> Int32 { _simdMinS(v) }
public func simdMax(_ v: Int32) -> Int32 { _simdMaxS(v) }

// MARK: - UInt32 reductions (unsigned: .u tag)

@_silgen_name("air.simd_sum.u.i32")
func _simdSumU(_ v: UInt32) -> UInt32
@_silgen_name("air.simd_product.u.i32")
func _simdProductU(_ v: UInt32) -> UInt32
@_silgen_name("air.simd_min.u.i32")
func _simdMinU(_ v: UInt32) -> UInt32
@_silgen_name("air.simd_max.u.i32")
func _simdMaxU(_ v: UInt32) -> UInt32

public func simdSum(_ v: UInt32) -> UInt32 { _simdSumU(v) }
public func simdProduct(_ v: UInt32) -> UInt32 { _simdProductU(v) }
public func simdMin(_ v: UInt32) -> UInt32 { _simdMinU(v) }
public func simdMax(_ v: UInt32) -> UInt32 { _simdMaxU(v) }

// MARK: - Ballot

@_silgen_name("air.simd_ballot.i64")
func _simdBallot(_ pred: Bool) -> UInt64

/// A lane mask (one bit per lane) of the lanes for which `pred` is true.
public func simdBallot(_ pred: Bool) -> UInt64 { _simdBallot(pred) }
