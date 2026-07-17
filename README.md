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

## Kernel language restrictions (the GPU-safe Swift subset)

GPU kernels run on hardware with **no heap, no runtime, and no dynamic
dispatch**, so a kernel is a restricted subset of Swift. The compiler must
*reject* (with a clear diagnostic) any construct that would need facilities the
GPU doesn't have — mirroring the features Metal Shading Language prohibits.
Banned in kernel code:

- **Dynamic memory allocation** — no `class` instances, no escaping closures, no
  growable `Array`/`Set`/`Dictionary`, no `String`. Anything that would call the
  allocator. (Fixed-size local values and `device`/`threadgroup` buffers only.)
- **ARC / reference counting** — reference types imply heap + retain/release,
  which don't exist on the GPU. Value types only.
- **Concurrency** — `async`/`await`, `Task`, actors. These rely on the heap
  (task allocation) and a runtime executor, so they're prohibited — same reason
  MSL has no threads-within-a-thread. (GPU parallelism comes from the dispatch
  grid, not `Task`.)
- **Recursion** — MSL forbids recursive functions (no call stack for it); the
  call graph must be statically finite. (Enables full inlining.)
- **Existentials / dynamic dispatch / metatypes** — protocol-typed values,
  `as?` to a class, witness tables, reflection. No runtime type metadata on GPU.
- **Error handling** (`throws`/`try`) — uses existential errors + heap.
- **The runtime & Foundation** — `print`, `Mirror`, `Codable`, Foundation, any
  library call that isn't a pure, inlinable, heap-free computation.

Allowed: value types (structs, tuples, enums without heap payloads), `SIMD`
types, fixed arithmetic, control flow, `device`/`constant`/`threadgroup` pointer
access, and the GPU builtins/intrinsics. Enforcing this subset with real
diagnostics (rather than a confusing downstream failure) is itself a roadmap
item — see below.

## Roadmap

- [x] End-to-end: Swift kernel → AIR → GPU execution (the `add` slice)
- [x] `smc` driver + IR→AIR transform + inference + unit tests
- [x] Vector types (`SIMD4<Float>` → `float4`) via generic wrapper-type flattening
- [x] Multiple builtins in one kernel (`indices` example)
- [x] **`@Compute`/`@Binding(to:)`/`@ThreadPositionInGrid` as real compiler
      attributes** in the swift-gpu fork; IRGen emits `!swiftgpu.kernels`
      metadata that `smc` reads directly — source parsing (`SwiftSignature`) retired
- [x] **Native GPU address spaces** — `@Device`/`@Constant`/`@Threadgroup`/`@Thread`
      as pointer-type qualifiers (Clang/MSL model: the address space qualifies the
      *pointee*). IRGen emits `ptr addrspace(N)` natively (device=1/constant=2/
      threadgroup=3), value-transparent (drop-on-load) but pointer-distinct (no AS
      mixing). Works on params *and* local `var`s; GPU-verified (`examples/devadd`)
- [x] **`swift-frontend -emit-air` / `-emit-metallib`** — the compiler owns the
      whole pipeline. An in-IRGen normalization pass swaps the AIR
      triple/datalayout, strips `swiftcc`/`nuw`/`captures(none)`/host fn-attrs +
      the `"PIC Level"` flag + `!prof` metadata, expands `splat` constants to
      `shufflevector`, and converts `!swiftgpu.kernels` → `air.kernel`/`air.buffer`.
      `-emit-metallib` then invokes `metal-as`/`metallib` in-process → a loadable
      library, **no `smc` transform**. All examples build this way.
- [x] **Typed (non-opaque) pointers** — the printed AIR is rewritten to
      `float addrspace(1)*` (and Swift wrapper structs flattened to their MSL
      leaf: `%TSf`→`float`, SIMD→`<4 x float>`, `InlineArray`→`[N x T]`), which
      the driver back-end requires. Reconstructed textually since the fork's LLVM
      is opaque-only.
- [x] **SIMD operator overloads on device values** (`device SIMD4<Float> * 2.0`)
      — the address-space qualifier is transparent to associated-type resolution,
      member substitution, and witness dispatch (`examples/dvscale`/`vscale`)
- [x] **Constant global data** — a program-scope `let table: InlineArray<N,Float>`
      is placed in the constant address space (`addrspace(2)`) and baked into the
      metallib (`examples/constdata`)
- [x] **Integer kernels** — Swift's overflow-checked `*`/`+` (with `llvm.trap`
      branches) assemble after `!prof` (branch_weights) stripping (`examples/intmath`)
- [x] Examples ported to `@Device` + the native pipeline (`add`/`vscale`/`indices`)
- [x] **Multiple kernels per module** — several `@Compute` functions → several
      `air.kernel` entries in one metallib, dispatched by name (`examples/multikernel`)
- [x] **Scalar/vector types** — `Float`/`Int32`/`UInt32`/`Float16` and
      `SIMD2`/`SIMD3`/`SIMD4` as buffer element types (flattened to MSL leaves)
- [x] **Thread builtins** — 6 position/count builtins, plus vector builtins for
      2-D/3-D dispatch (`uint2`/`uint3` `thread_position_in_grid`, `examples/grid2d`)
- [x] **Device values in non-uniform expressions** — a device-loaded scalar mixes
      with non-device values in generic operators/initializers, and computed
      values store into device locations (the qualifier is storage-only and drops
      on load) — `examples/grid2d`
- [ ] Fully retire `smc`: `swiftc` driver routing for `-emit-air`/`-emit-metallib`
      (currently via `swift-frontend`; needs `swift-driver` support)
- [x] **Threadgroup shared memory** — `@Threadgroup` buffers (AIR addrspace 3,
      host-allocated), the `air.wg.barrier` intrinsic, and a `dispatchThreadgroups`
      host API; GPU-verified per-threadgroup reduction (`examples/reduce`). The
      GPU pipeline disables host auto-vectorization (its `<N x T>` /
      `llvm.vector.reduce.*` output can't be lowered by the AIR back-end).
- [x] **Textures** (first package) — Swift-authored texture kernels work
      end-to-end. `Texture2D`/`WriteTexture2D`/`ReadWriteTexture2D<Float>` are
      package types the compiler lowers to `air.texture` args (opaque
      `ptr addrspace(1)`, no named struct); `.read`/`.write` call the `air.*`
      intrinsics. Read/write/read_write access; `Float`/`Float16`/`UInt32`/`Int32`
      element formats; 2-D and 3-D; **filtered `sample()`** through a `Sampler`
      argument. `examples/texture`, `rwtexture`, `utexture`, `texture3d`,
      `sample` (bilinear upsample) — GPU-verified. Binding slots via `@Binding(to:)`
      (kind from the type — no `@Texture`/`@Sampler` attribute). See `docs/textures.md`.
- [x] **Atomics** (second package) — fetch add/sub/max/min/and/or/xor on `UInt32`
      *and* `Int32`, float atomic add, load/store, exchange, and compare-exchange,
      over the `air.atomic.global.*` intrinsics (no special type — MSL atomics are
      just device i32/f32). `examples/histogram` + `examples/atomics` (CAS-loop
      counter), GPU-verified. See `docs/atomics.md`.
- [x] **Enforce the GPU-safe subset** — `@Compute` kernels are checked after
      type-checking and rejected with a source-level diagnostic for `throws`,
      `async`, non-`Void` return, and heap/ARC/existential values (class, `any P`,
      `Array`/`String`/`Dictionary`/`Set`, `print`). Type-based, so
      `InlineArray`/`SIMD` literals are fine. A pre-`-O` SIL call-graph check
      follows the kernel's transitive calls into user helpers for **recursion**
      (direct/mutual) and **heap allocation**; a post-`-O` backstop then walks the
      fully-optimized reachable graph (incl. stdlib) and rejects any surviving
      allocation or **call to a runtime function with no GPU implementation**
      (e.g. `Int.random` → `swift_stdlib_random`) — so a kernel referencing
      anything unavailable on the GPU fails at compile time rather than producing
      a broken metallib. See `docs/gpu-safe-subset.md`.
- [ ] AIR intrinsics (SIMD-group ops, simdgroup matrices, MetalPerformancePrimitives)
- [ ] Graphics stages (`@Vertex`/`@Fragment`), then a CUDA/NVPTX backend

## Layout

- `Sources/` — `GPUSwift`, `AIRBackend`, `MetalSwift`, `smc` (see table above)
- `Tests/AIRBackendTests` — transform unit tests (no GPU/swiftc needed)
- `examples/` — each has a kernel + host + `build.sh` (native `-emit-metallib`):
  `add`, `vscale`, `indices`, `devadd`, `dvscale`, `constdata`, `intmath`

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
