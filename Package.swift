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
    ]
)
