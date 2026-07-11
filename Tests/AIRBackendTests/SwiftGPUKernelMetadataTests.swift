import XCTest
import GPUSwift
@testable import AIRBackend

final class SwiftGPUKernelMetadataTests: XCTestCase {
    /// Verbatim shape of the `!swiftgpu.kernels` metadata the fork's IRGen emits.
    let ir = """
    define void @add(ptr %0, ptr %1, ptr %2, i32 %3) {
      ret void
    }
    !swiftgpu.kernels = !{!16}
    !16 = !{ptr @add, !"compute", !17}
    !17 = !{!18, !19, !20, !21}
    !18 = !{i32 0, !"buffer", i32 0, !"UnsafePointer<Float>", !"a"}
    !19 = !{i32 1, !"buffer", i32 1, !"UnsafePointer<Float>", !"b"}
    !20 = !{i32 2, !"buffer", i32 2, !"UnsafeMutablePointer<Float>", !"out"}
    !21 = !{i32 3, !"threadPositionInGrid", i32 -1, !"UInt32", !"gid"}
    """

    func testReadsBindingContractFromMetadata() throws {
        let iface = try XCTUnwrap(try SwiftGPUKernelMetadata.parse(ir: ir, kernel: "add"))
        XCTAssertEqual(iface.arguments.map(\.name), ["a", "b", "out", "gid"])

        guard case let .buffer(i0, s0, acc0, elem0, _) = iface.arguments[0] else { return XCTFail() }
        XCTAssertEqual(i0, 0); XCTAssertEqual(s0, .device)
        XCTAssertEqual(acc0, .read); XCTAssertEqual(elem0.airName, "float")

        guard case let .buffer(_, _, acc2, _, _) = iface.arguments[2] else { return XCTFail() }
        XCTAssertEqual(acc2, .readWrite)   // UnsafeMutablePointer

        guard case .builtin(.threadPositionInGrid, "uint", "gid") = iface.arguments[3] else {
            return XCTFail("arg3 should be thread_position_in_grid uint")
        }
    }

    func testRespectsExplicitBindingSlots() throws {
        // Slots deliberately not in parameter order.
        let ir2 = """
        !swiftgpu.kernels = !{!1}
        !1 = !{ptr @k, !"compute", !2}
        !2 = !{!3, !4}
        !3 = !{i32 0, !"buffer", i32 5, !"UnsafeMutablePointer<Float>", !"out"}
        !4 = !{i32 1, !"threadPositionInGrid", i32 -1, !"UInt32", !"gid"}
        """
        let iface = try XCTUnwrap(try SwiftGPUKernelMetadata.parse(ir: ir2, kernel: "k"))
        guard case let .buffer(idx, _, _, _, _) = iface.arguments[0] else { return XCTFail() }
        XCTAssertEqual(idx, 5, "explicit @Binding(to: 5) must win over position")
    }

    func testAbsentMetadataReturnsNil() throws {
        XCTAssertNil(try SwiftGPUKernelMetadata.parse(ir: "define void @x() {\n ret void\n}", kernel: "x"))
    }

    func testEndToEndTransformFromMetadata() throws {
        // The reader feeds IRToAIR: buffers land in addrspace(1), builtin becomes
        // thread_position_in_grid.
        let full = """
        target datalayout = "e"
        target triple = "arm64-apple-macosx26.0.0"
        define swiftcc void @add(ptr readonly captures(none) %0, ptr readonly captures(none) %1, ptr writeonly captures(none) %2, i32 %3) {
        entry:
          %4 = zext i32 %3 to i64
          %5 = getelementptr inbounds float, ptr %0, i64 %4
          %6 = load float, ptr %5, align 4
          %7 = getelementptr inbounds float, ptr %2, i64 %4
          store float %6, ptr %7, align 4
          ret void
        }
        \(ir.components(separatedBy: "define void @add(ptr %0, ptr %1, ptr %2, i32 %3) {\n  ret void\n}\n").last ?? "")
        """
        let iface = try XCTUnwrap(try SwiftGPUKernelMetadata.parse(ir: full, kernel: "add"))
        let (air, _) = try IRToAIR.generate(ir: full, kernelName: "add", interface: iface)
        XCTAssertTrue(air.contains("ptr addrspace(1) noundef \"air-buffer-no-alias\" %0"))
        XCTAssertTrue(air.contains("air.thread_position_in_grid"))
        XCTAssertTrue(air.contains("!\"air.arg_name\", !\"a\""))
    }
}
