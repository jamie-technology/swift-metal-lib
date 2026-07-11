# Swift Metal

Write Metal compute kernels in Swift and compile them to Apple AIR — a loadable
`.metallib` you can run through `Metal.framework`.

**Status:** an end-to-end vertical slice works today. A Swift function compiles,
via the real toolchain, to AIR that executes correctly on the GPU. See
[`examples/add`](examples/add).

```
$ ./examples/add/build.sh
smc: compiled 'add' → examples/add/add.metallib
       arg[0] arg0: device read float* @ buffer(0)
       arg[1] arg1: device read float* @ buffer(1)
       arg[2] arg2: device readWrite float* @ buffer(2)
       arg[3] gid: air.thread_position_in_grid
✅ add: GPU result matches CPU for all 1048576 elements  (out[42] = 126.0)
```

## How it works

The key observation (validated end-to-end) is that **AIR is LLVM bitcode**, and
`swiftc -emit-ir -O` already produces LLVM IR for a leaf kernel function that is
only a handful of mechanical edits away from loadable AIR. So the compiler is,
for now, a **transform**, not a fork:

```
add.swift ──swiftc -emit-ir -O──▶ LLVM IR ──IR→AIR transform──▶ textual AIR
          ──metal-as──▶ .air (bitcode) ──metallib──▶ add.metallib ──▶ MTLLibrary
```

The transform (`Sources/AIRBackend`) does exactly this:

1. swap the target triple/datalayout for AIR's (`air64_v28`, no native i64);
2. drop Swift-runtime globals & metadata (reflection, module flags);
3. normalise Swift's scalar-wrapper structs (`%TSf` → `float`);
4. strip `swiftcc` and rewrite `device` buffer pointers into `addrspace(1)`,
   propagating the address space through every derived pointer;
5. emit AIR's entry-point + argument metadata contract (`!air.kernel`, per-arg
   `air.buffer` / `air.thread_position_in_grid` nodes).

The binding contract comes from **real compiler attributes**. The swift-gpu
fork understands `@Compute`, `@Binding(to:)`, and the thread/grid builtins
(`@ThreadPositionInGrid`, …); its IRGen records them into a `!swiftgpu.kernels`
named-metadata node, one entry per kernel with each parameter's role, buffer
slot, type, and name. `smc` reads that metadata (`SwiftGPUKernelMetadata`) — it
never re-parses the Swift source. See the AIR docs at
`~/Developer/metal-air-documentation/docs/08-emitting-air-a-backend-guide.md`.

### Fork changes required

This needs the GPU-capable `swiftc`. The patches to the swift-gpu fork (each
`.smc-bak`-backed) add the attributes and the metadata emission — see
`docs/fork-changes.md` for the exact file list. `smc` finds the fork `swiftc`
via `$SWIFT_GPU_SWIFTC` or `--swiftc` (default: the local `swift-gpu-fork` build).

## Architecture

Three seams, so a second backend (CUDA/NVPTX — also an LLVM target) and eventual
in-compiler integration both drop in cleanly:

| Layer | Target | Role | Fate |
| --- | --- | --- | --- |
| **GPUSwift** | `Sources/GPUSwift` | Target-neutral model: address spaces, builtins, `KernelInterface` | Compiler-integrated eventually (needs Sema + IRGen) |
| **AIRBackend** | `Sources/AIRBackend` | The IR→AIR transform + metadata emitter (Metal-specific) | Pluggable; a `PTXBackend` would sit beside it |
| **MetalSwift** | `Sources/MetalSwift` | Host-side runtime helpers (load a `.metallib`, dispatch) | Apple-platform interop |
| **smc** | `Sources/smc` | Driver: orchestrates swiftc → transform → metal-as/metallib | — |

### Why we will still need compiler integration

The *mechanism* needs no fork, but the *attribute surface* does. Swift's Sema
rejects unknown attributes, and — more fundamentally — no macro can make IRGen
emit `addrspace(1)`. Post-processing recovers address spaces today, but a robust
system (threadgroup memory, atomics, textures) wants them correct at the source
of truth. The plan: bootstrap with the transform (which *is* the reference AIR
the native path must match), then promote `@Compute`/`@Binding`/… to
compiler-known attributes with a real AIR IRGen path in the fork. Keeping the
user-facing library standalone (not in-tree) until then avoids coupling to the
1.5-hour compiler rebuild and the Swift release train.

### On MPS / MetalPerformancePrimitives

- **MetalPerformanceShaders** is host-side prebuilt-kernel dispatch — pure
  `Metal.framework` interop, orthogonal to this compiler. Wrap thinly if/when
  needed; defer.
- **MetalPerformancePrimitives** are *in-shader* primitives (simdgroup matrices,
  tensor ops) that lower to `air.*` intrinsics — part of the future shader
  stdlib, built after the core codegen path solidifies. A lowering, not a wrapper.

## Roadmap

- [x] End-to-end: Swift kernel → AIR → GPU execution (the `add` slice)
- [x] `smc` driver + IR→AIR transform + inference + unit tests
- [x] Vector types (`SIMD4<Float>` → `float4`) via generic wrapper-type flattening
- [x] Multiple builtins in one kernel (`indices` example)
- [x] **`@Compute`/`@Binding(to:)`/`@ThreadPositionInGrid` as real compiler
      attributes** in the swift-gpu fork; IRGen emits `!swiftgpu.kernels`
      metadata that `smc` reads directly — source parsing (`SwiftSignature`) retired
- [ ] **Next:** native address-space codegen in IRGen (retire the post-processing pass)
- [ ] More builtins & scalar/vector types; multiple kernels per module
- [ ] `constant` / `threadgroup` address spaces; atomics; textures
- [ ] AIR intrinsics (SIMD-group ops, simdgroup matrices, MetalPerformancePrimitives)
- [ ] Graphics stages (`@Vertex`/`@Fragment`), then a CUDA/NVPTX backend

## Layout

- `Sources/` — `GPUSwift`, `AIRBackend`, `MetalSwift`, `smc` (see table above)
- `Tests/AIRBackendTests` — transform unit tests (no GPU/swiftc needed)
- `examples/add` — the reference elementwise-add kernel + host + `build.sh`

## Kernel design (target attribute surface)

The intended source-level design, once the compiler carries the attributes:

- Functions: `@Vertex`, `@Fragment`, `@Compute`, `@Intersection(of:)`, `@Patch(of:)`
- Arguments: `@Binding(to:)`, thread-position builtins
  (`@ThreadPositionInGrid`, `@ThreadPositionInThreadgroup`,
  `@ThreadgroupPositionInGrid`, `@ThreadIndexInThreadgroup`,
  `@ThreadgroupsPerGrid`, `@Threadgroup(idx)`, `@SimdgroupIndexInThreadgroup`),
  memory semantics (`@Device`, `@Const`), `@TextureBinding(to:)`,
  `@VertexIdentifier`, `@InstanceIdentifier`, `@StageIn`
- Structures: `@GPU`; properties `@Binding(to:)`, `@Attribute(index:)`,
  `@Position`, `@PointSize`, `@Flat`, `@CenterNoPerspective`

### Open questions

- How to represent `texture2d<float, access::read>` — a generic `Texture` type?
  How to encode `access::read` etc.?
- Raytracing: `@Payload`, `@Distance`, `@PrimitiveIdentifier`, `@BarycentricCoord`
- Mesh shaders; vertex amplification & fragment barycentrics; tile shading / imageblocks
