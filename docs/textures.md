# Textures (the first package)

Textures are the first swift-metal feature delivered as a **package** layered on
compiler primitives. Kernels are written in Swift and compiled by the fork.

## Status: working end-to-end

`examples/texture` inverts a 64×64 image (RGB inverted, alpha preserved),
GPU-verified — kernel authored in Swift, compiled by `swift-frontend
-emit-metallib`.

```swift
@Compute @_silgen_name("invert")
public func invert(_ src: Texture2D<Float>, _ dst: WriteTexture2D<Float>,
                   @ThreadPositionInGrid _ gid: SIMD2<UInt32>) {
    let c = src.read(gid)
    dst.write(SIMD4<Float>(1 - c.x, 1 - c.y, 1 - c.z, c.w), to: gid)
}
```

## The two halves

**GPU-side (the package, `packages/Textures/Textures.swift`)** — `Texture2D<T>` /
`WriteTexture2D<T>` handle types + `read`/`write`, calling the `air.*` texture
intrinsics via `@_silgen_name`. Compiled alongside the kernel.

**Host (`MetalSwift`)** — `ComputeContext.texture(width:height:pixels:usage:)`,
`dispatchTextures(_:textures:width:height:)`, `MTLTexture.floats()`.

## Compiler support (fork)

- **Texture type lowering.** `Texture2D`/`WriteTexture2D` each wrap a single
  `@Device` pointer field, so they flatten to an opaque `ptr addrspace(1)` — the
  driver accepts an opaque device pointer for the texture arg *and* the
  `air.read/write_texture_2d` intrinsic operands, keyed off `air.texture`
  metadata (no named `%struct._texture_2d_t` needed). The sampler is a
  `@Constant` field → `ptr addrspace(2)`.
- **`air.texture` metadata.** `IRGenModule.cpp` tags a parameter whose nominal
  type is `Texture2D`/`WriteTexture2D` with a `textureRead`/`textureWrite` role;
  the normalize pass (`IRGen.cpp`) emits an `air.texture` node with the access
  qualifier (`air.read`/`air.write`), numbered in the `[[texture(N)]]` namespace.
- **Intrinsics.** `air.read_texture_2d.v4f32` (returns `{<4 x float>, i8}`),
  `air.write_texture_2d.v4f32`, `air.get_read_sampler` — declared from Swift with
  `@_silgen_name`. `(SIMD4<Float>, UInt8)` matches the `{<4 x float>, i8}` return.
- **Runtime-metadata stripping.** User nominal types (Texture2D) drag in Swift
  type descriptors / value witnesses / metadata accessors that metal-as can't
  parse. The GPU path disables reflection metadata (`CompilerInvocation.cpp`) and
  the normalize pass erases the `$s…`/`__swift…`/`swift_…` runtime symbols (they
  form a mutually-referential cluster no kernel references; GPU *data* globals in
  addrspace 1/2/3 are kept).
- **Opaque, not typed.** The typed-pointer pass only runs when a constant-address-
  space global is present; texture/device kernels stay fully opaque (which the
  driver accepts). Typing is all-or-nothing, so a half-typed module (typed loads
  + opaque `air.*` operands) is avoided.

## Access & dimensions

Access is per-type: `Texture2D` (read), `WriteTexture2D` (write),
`ReadWriteTexture2D` (`access::read_write`, `examples/rwtexture` — in-place
brighten, GPU-verified). The compiler recovers dimension + access from the type
name: a single `texture` role in `!swiftgpu.kernels`, and the normalize pass
parses the recorded Swift type into `air.read`/`air.write`/`air.read_write` +
`texture2d`/`texture3d<float, …>`.

`Texture3D`/`WriteTexture3D` exist and their read/write intrinsics + metadata
assemble, but **3-D dispatch is blocked on the uint3 gap**: it needs a uint3
`thread_position_in_grid` (`<3 x i32>`), and Swift's `SIMD3<UInt32>` lowers to
`<4 x i32>` (padded). Fixing uint3 (lowering/rewriting `<4 x i32>` → `<3 x i32>`
for 3-component builtins) unblocks 3-D grids generally, including 3-D textures.

## Not yet

- uint3 (3-D dispatch / `Texture3D`), other element types/formats (`half` =
  `.v4f16`, `uint`/`int` = `.v4u32`/`.v4i32`), `sample()` with explicit samplers,
  1D/array/cube textures, mip levels.
- A kernel mixing textures *and* a constant global (would force typed pointers,
  which don't yet type the opaque texture/sampler operands).
