// Triangle — a minimal graphics pipeline written in Swift. A @Vertex stage
// expands [[vertex_id]] 0/1/2 into a viewport-filling triangle (the clip-space
// positions (-1,-1), (3,-1), (-1,3)); a @Fragment stage returns a constant
// colour to [[color(0)]]. The fork lowers these to air.vertex / air.fragment
// entry points in the metallib — no compute kernel involved.

@Vertex
@_silgen_name("triangle_vertex")
public func triangleVertex(@VertexID _ vid: UInt32) -> SIMD4<Float> {
    let x: Float = vid == 1 ? 3 : -1
    let y: Float = vid == 2 ? 3 : -1
    return SIMD4<Float>(x, y, 0, 1)
}

@Fragment
@_silgen_name("triangle_fragment")
public func triangleFragment() -> SIMD4<Float> {
    return SIMD4<Float>(1, 0, 0, 1)   // opaque red
}
