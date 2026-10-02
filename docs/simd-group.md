# SIMD-group operations

The `SIMDGroup` package (`packages/SIMDGroup`) exposes GPU SIMD-group (subgroup /
warp) collectives — reductions, scans, shuffles, broadcasts, and ballot — on top
of the `air.simd_*` intrinsics. A SIMD-group is the set of threads (**32 lanes**
on Apple GPUs) that execute in lockstep on one execution unit; these ops let them
cooperate directly, with no threadgroup memory and no barrier.

Like `Textures` and `Atomics`, it needs no dedicated type: each op is a thin
`public func` over an `@_silgen_name("air.simd_…")` intrinsic (the AIR normalizer
already marks every `air.*` declaration `convergent` and cleans its attributes).

```swift
import  // (compiled in alongside the kernel, not imported)
@Compute
@_silgen_name("simdreduce")
public func simdreduce(@Binding(to: 0) @Device _ input: UnsafePointer<Float>,
                       @Binding(to: 1) @Device _ output: UnsafeMutablePointer<Float>,
                       @ThreadPositionInGrid _ gid: UInt32) {
    output[Int(gid)] = simdSum(input[Int(gid)])   // every lane gets the group sum
}
```

## What's provided

| Group | Ops |
| --- | --- |
| Float reductions | `simdSum` `simdProduct` `simdMin` `simdMax` |
| Float scans | `simdPrefixExclusiveSum` `simdPrefixInclusiveSum` |
| Float shuffles | `simdShuffle` `simdShuffleXor` `simdShuffleUp` `simdShuffleDown` `simdBroadcast(_:from:)` `simdBroadcastFirst` |
| Int32 / UInt32 reductions | `simdSum` `simdProduct` `simdMin` `simdMax` (overloaded) |
| Ballot | `simdBallot(_:) -> UInt64` |

The intrinsic grammar is `air.simd_<op>[.<sign>].<type>`: the `.s`/`.u`
signedness tag appears on the integer reductions, float ops are just `.f32`, and
lane/mask arguments are `i16` (`UInt16` in the API). See
[metal-air-documentation `04-simd-group-operations`](https://github.com/jamie-technology/metal-air-documentation/blob/main/docs/04-simd-group-operations.md).

## Compiler note — typed pointers

This was the one compiler change SIMD-group ops required. The AIR normalizer
leaves plain device/texture kernels with **opaque** pointers (which the driver
accepts), and only reconstructs **typed** pointers when the module needs them.
A SIMD-group intrinsic needs them: the AGX driver's bitcode upgrader rejects an
opaque module containing `air.simd_*` with *"Failed to upgrade function
bitcode"* (the real `metal` compiler's output for these is fully typed). So the
typed-pointer rewrite's gate (`rewriteAIRToTypedPointers` in `FrontendTool.cpp`)
now also fires when the AIR text contains `@air.simd` — covering both the
`air.simd_*` ops here and the `air.simdgroup_matrix_*` family. See
`docs/fork-changes.md`.

## Example

`examples/simdreduce` — 32 threads (one Apple SIMD-group) cooperatively sum their
inputs with `simdSum`; every lane writes the group total. Dispatched as a single
threadgroup of 32 so one SIMD-group covers the grid. GPU-verified (sum of
1…32 = 528).
