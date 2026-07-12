# Textures (the first package)

Textures are the first feature delivered as a **package** rather than baked into
the core: a `MetalTextures` surface (host + GPU-side API) layered on the compiler
primitives. This doc records the feasibility findings and the remaining compiler
work; the host path is implemented and GPU-verified today.

## Status

- **Host support — done & verified.** `ComputeContext.texture(width:height:pixels:
  usage:)`, `dispatchTextures(_:textures:width:height:)`, and `MTLTexture.floats()`
  (`Sources/MetalSwift/Runtime.swift`). Verified end-to-end on GPU with an MSL-
  compiled `invert` kernel (`examples/texture` — RGB inverted, alpha preserved).
- **Compiler support — not yet.** The Swift-authored kernel needs a texture
  *type* and read/write intrinsics (below). Until then, `examples/texture` runs
  against an MSL-compiled `.metallib`.

## What AIR a texture kernel needs

From `xcrun metal -S -emit-llvm` on a `texture2d<float>` read/write kernel:

```llvm
%struct._texture_2d_t = type opaque
%struct._sampler_t    = type opaque

define void @invert(%struct._texture_2d_t addrspace(1)* readonly %0,   ; [[texture(0)]]
                    %struct._texture_2d_t addrspace(1)* %1,            ; [[texture(1)]]
                    <2 x i32> %2) {                                    ; uint2 gid
  %s = call %struct._sampler_t addrspace(2)* @air.get_read_sampler()
  %r = call { <4 x float>, i8 } @air.read_texture_2d.v4f32(
           %struct._texture_2d_t addrspace(1)* %0, %struct._sampler_t addrspace(2)* %s,
           <2 x i32> %2, <2 x i32> zeroinitializer, i32 0, i32 1)
  ; ... compute ...
  call void @air.write_texture_2d.v4f32(
           %struct._texture_2d_t addrspace(1)* %1, <2 x i32> %2, <4 x float> %c, i32 0, i32 2)
}
```

Metadata: an `air.texture` argument node (not `air.buffer`) —
`!{i32 0, !"air.texture", !"air.location_index", i32 0, i32 1, !"air.read",
!"air.arg_type_name", !"texture2d<float, read>", !"air.arg_name", !"src"}`,
with `air.read` / `air.write` / `air.read_write` for the access qualifier.

## Remaining compiler work

1. **Texture type.** A `Texture2D<Float>` (and access variants) that IRGen lowers
   to a device-address-space handle. **Verified:** the driver accepts an opaque
   `ptr addrspace(1)` for the texture arg *and* the intrinsic operands, keyed off
   the `air.texture` metadata — so no named `%struct._texture_2d_t` needs to be
   synthesized (`examples/texture` runs on an opaque-pointer AIR kernel). The
   texture type just needs to lower to `ptr addrspace(1)` (like a `@Device`
   pointer with an opaque pointee).
2. **`@Texture(access:)` parameter attribute** — like `@Binding`/`@Device`, but
   emits an `air.texture` metadata node with the access qualifier, numbered in the
   `[[texture(N)]]` index namespace (as the threadgroup work did for
   `[[threadgroup(N)]]`).
3. **Read/write intrinsics** — `air.read_texture_2d.v4f32`,
   `air.write_texture_2d.v4f32`, `air.get_read_sampler`, declared from Swift via
   `@_silgen_name` (the barrier established that `air.*` externals work; the
   normalize pass already marks `air.*` calls `convergent` and cleans their
   attributes). The read intrinsic returns `{<4 x float>, i8}` (texel + status).

## GPU-side packaging

Kernels are compiled standalone (`swift-frontend` on one file), so the GPU-side
texture API (type + intrinsic wrappers) lives in a header-like Swift file the
kernel includes, the same way `examples/reduce` declares the barrier. The
`MetalTextures` package bundles that GPU-side file plus the host helpers above.
