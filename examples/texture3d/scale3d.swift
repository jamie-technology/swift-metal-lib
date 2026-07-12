// 3-D texture: scale each voxel by 0.5 (uint3 thread position).
@Compute @_silgen_name("scale3d")
public func scale3d(_ src: Texture3D<Float>, _ dst: WriteTexture3D<Float>,
                    @ThreadPositionInGrid _ gid: SIMD3<UInt32>) {
    dst.write(src.read(gid) * 0.5, to: gid)
}
