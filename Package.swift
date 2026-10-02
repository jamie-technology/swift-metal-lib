// swift-tools-version:5.9
import PackageDescription

// swift-metal — write GPU kernels in Swift, compile them to Apple AIR (and,
// later, other LLVM GPU backends such as NVPTX/CUDA).
//
// Layering (see README "Architecture"):
//   • GPUSwift   — target-neutral model of GPU execution: address spaces,
//                  builtins, and the kernel-interface descriptor. The seam a
//                  second backend (CUDA) plugs into. Destined for the compiler
//                  eventually; standalone for now.
//   • MetalSwift — host runtime helpers (load a .metallib, dispatch a kernel).
//                  Apple-platform only.
//   • smc        — the "swift-metal compiler" driver: swiftc -emit-ir  ->
//                  IR->AIR transform  ->  metal-as / metallib.
let package = Package(
    name: "swift-metal",
    products: [
        .library(name: "GPUSwift", targets: ["GPUSwift"]),
        .library(name: "AIRBackend", targets: ["AIRBackend"]),
        .library(name: "MetalSwift", targets: ["MetalSwift"]),
        .executable(name: "smc", targets: ["smc"]),
    ],
    targets: [
        .target(name: "GPUSwift"),
        .target(name: "AIRBackend", dependencies: ["GPUSwift"]),
        .target(name: "MetalSwift", dependencies: ["GPUSwift"]),
        .executableTarget(name: "smc", dependencies: ["AIRBackend", "GPUSwift"]),
        .testTarget(name: "AIRBackendTests", dependencies: ["AIRBackend", "GPUSwift"]),
        // Example host programs. The *shaders* (examples/*/*.swift) are compiled
        // by `smc`, not SwiftPM; only the host lives in a package target.
        .executableTarget(name: "add-example", dependencies: ["MetalSwift"],
                          path: "examples/add/Host"),
        .executableTarget(name: "vscale-example", dependencies: ["MetalSwift"],
                          path: "examples/vscale/Host"),
        .executableTarget(name: "indices-example", dependencies: ["MetalSwift"],
                          path: "examples/indices/Host"),
        .executableTarget(name: "devadd-example", dependencies: ["MetalSwift"],
                          path: "examples/devadd/Host"),
        .executableTarget(name: "dvscale-example", dependencies: ["MetalSwift"],
                          path: "examples/dvscale/Host"),
        .executableTarget(name: "constdata-example", dependencies: ["MetalSwift"],
                          path: "examples/constdata/Host"),
        .executableTarget(name: "intmath-example", dependencies: ["MetalSwift"],
                          path: "examples/intmath/Host"),
        .executableTarget(name: "multikernel-example", dependencies: ["MetalSwift"],
                          path: "examples/multikernel/Host"),
        .executableTarget(name: "grid2d-example", dependencies: ["MetalSwift"],
                          path: "examples/grid2d/Host"),
        .executableTarget(name: "grid3d-example", dependencies: ["MetalSwift"],
                          path: "examples/grid3d/Host"),
        .executableTarget(name: "reduce-example", dependencies: ["MetalSwift"],
                          path: "examples/reduce/Host"),
        .executableTarget(name: "texture-example", dependencies: ["MetalSwift"],
                          path: "examples/texture/Host"),
        .executableTarget(name: "rwtexture-example", dependencies: ["MetalSwift"],
                          path: "examples/rwtexture/Host"),
        .executableTarget(name: "texture3d-example", dependencies: ["MetalSwift"],
                          path: "examples/texture3d/Host"),
        .executableTarget(name: "utexture-example", dependencies: ["MetalSwift"],
                          path: "examples/utexture/Host"),
        .executableTarget(name: "sample-example", dependencies: ["MetalSwift"],
                          path: "examples/sample/Host"),
        .executableTarget(name: "histogram-example", dependencies: ["MetalSwift"],
                          path: "examples/histogram/Host"),
        .executableTarget(name: "atomics-example", dependencies: ["MetalSwift"],
                          path: "examples/atomics/Host"),
        .executableTarget(name: "simdreduce-example", dependencies: ["MetalSwift"],
                          path: "examples/simdreduce/Host"),
        .executableTarget(name: "triangle-example", dependencies: ["MetalSwift"],
                          path: "examples/triangle/Host"),
        .executableTarget(name: "sgemm-example", dependencies: ["MetalSwift"],
                          path: "examples/sgemm/Host"),
    ]
)
