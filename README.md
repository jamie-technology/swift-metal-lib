# Swift Metal

Write Metal kernels in Swift, with a Swift compiler fork that targets AIR.

## Useful resources

- ~/Developer/metal-air-documentation: Metal test harnesses and AIR documentation.
- ~/Developer/swift-gpu/*: a checked out copy of the Swift repo, built and ready to ierate on

## Open design decisions

The Swift kernel design.

### Swift Kernel Design

- Functions should be annotated with @Vertex, @Fragment, @Compute, @Intersection(of: triangle, triagle_data), @Patch(of:...)
- Function arguments can be annotated with @Binding(to:) which takes an index to bind to
- Function arguments can be annotated with @ThreadPositionInGrid, @ThreadPositionInThreadgroup, @ThreadgroupPositionInGrid, @ThreadIndexInThreadgroup, @ThreadgroupsPerGrid, @Threadgroup(idx), @SimdgroupIndexInThreadgroup
- Function arguments can be annotated with memory semantics: @Device, @Const, 
- Function arguments can be annotated with @TextureBinding(to:), @VertexIdentifier, @InstanceIdentifier, @StageIn, 
- Structures should be annotated with @GPU
- Structure properties can be annotated with @Binding(to:), @Attribute(index:), @Position, @PointSize, @Flat, @CenterNoPerspective


#### Open questions

- How to represent texture2d<float, access::read>? A generic texture2d type? How do we represent access::read etc.?
- Raytracing: @Payload, @Distance, @PrimitiveIdentifier, @BarycentricCoord
- Mesh shaders
- vertex amplification and fragment barycentric coordinates
- tile shading / imageblocks.

How to integrate with the Swift compiler?

## Layout

- examples/
    - Swift programs that target Metal.framework AND use our custom swiftc to generate metallibs from Swift shaders.