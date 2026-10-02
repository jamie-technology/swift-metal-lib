# Graphics stages (`@Vertex` / `@Fragment`)

Beyond compute, the fork now compiles **graphics** shaders: a `@Vertex` stage and
a `@Fragment` stage, lowered to `air.vertex` / `air.fragment` entry points in the
metallib (not `air.kernel`). `RenderContext` in `MetalSwift` drives them
offscreen.

```swift
@Vertex
@_silgen_name("triangle_vertex")
public func triangleVertex(@VertexID _ vid: UInt32) -> SIMD4<Float> {
    let x: Float = vid == 1 ? 3 : -1
    let y: Float = vid == 2 ? 3 : -1
    return SIMD4<Float>(x, y, 0, 1)        // clip-space [[position]]
}

@Fragment
@_silgen_name("triangle_fragment")
public func triangleFragment() -> SIMD4<Float> {
    return SIMD4<Float>(1, 0, 0, 1)        // [[color(0)]]
}
```

```swift
let ctx = try RenderContext(metallibPath: "triangle.metallib")
let pixels = try ctx.render(vertex: "triangle_vertex", fragment: "triangle_fragment",
                            vertexCount: 3, width: 16, height: 16)   // BGRA bytes
```

## The mapping

| Swift | AIR |
| --- | --- |
| `@Vertex func(...) -> SIMD4<Float>` | `air.vertex` entry; the return is the `air.position` output |
| `@Fragment func(...) -> SIMD4<Float>` | `air.fragment` entry; the return is `air.render_target` 0 (`[[color(0)]]`) |
| `@VertexID _ vid: UInt32` | `air.vertex_id` input |
| `@InstanceID _ iid: UInt32` | `air.instance_id` input |
| `@Device`/`@Constant` pointer param | `air.buffer` input (pull-model vertex fetch) |

A `SIMD4<Float>` return lowers directly to `<4 x float>`; `swiftcc` is stripped
by the normalizer, and the normalizer adds the `air.compile_options` the
render-pipeline path expects. The stage string (`"vertex"`/`"fragment"`) travels
from `emitSwiftGPUKernelMetadata` through `!swiftgpu.kernels` to the normalizer,
which builds the stage-specific `air.vertex` / `air.fragment` node. See
`docs/fork-changes.md`.

## Example

`examples/triangle` — a viewport-filling triangle expanded from `[[vertex_id]]`,
shaded a constant red, rendered into a 16×16 texture and verified by reading the
center pixel back (GPU-verified).

## Scope / follow-ups

This is the minimal-but-real graphics path. Not yet supported (documented gaps):

- **`[[stage_in]]` attribute structs** — a `VertexIn { float3 position
  [[attribute(0)]]; … }` input struct and the vertex-descriptor plumbing.
- **Interpolated varyings** — a vertex returning a struct of `[[position]]` plus
  user varyings, matched to fragment inputs by the `generated(…)` linkage name.
  Today a vertex returns only its `[[position]]` and a fragment takes no
  interpolated inputs.
- **Depth/stencil, multiple render targets, blending.**

See [metal-air-documentation `00_passthrough`/`01_vertex_ids`](https://github.com/jamie-technology/metal-air-documentation/tree/main/harnesses/graphics)
for the full AIR shape these build toward.
