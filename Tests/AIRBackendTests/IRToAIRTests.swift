import XCTest
import GPUSwift
@testable import AIRBackend

final class IRToAIRTests: XCTestCase {
    /// Verbatim `swiftc -emit-ir -O` output for the add kernel (the shape the
    /// transform must handle). Kept as a fixture so the transform is testable
    /// without invoking swiftc or the GPU.
    let addIR = """
    ; ModuleID = '<swift-imported-modules>'
    source_filename = "<swift-imported-modules>"
    target datalayout = "e-m:o-p270:32:32-i64:64-n32:64-S128"
    target triple = "arm64-apple-macosx26.0.0"

    %TSf = type <{ float }>

    @__swift_reflection_version = linkonce_odr hidden constant i16 3
    @llvm.used = appending global [2 x ptr] [ptr @__swift_reflection_version, ptr @add], section "llvm.metadata"

    define swiftcc void @add(ptr readonly captures(none) %0, ptr readonly captures(none) %1, ptr writeonly captures(none) %2, i32 %3) #0 {
    entry:
      %4 = zext i32 %3 to i64
      %5 = getelementptr inbounds nuw %TSf, ptr %0, i64 %4
      %6 = load float, ptr %5, align 4
      %7 = getelementptr inbounds nuw %TSf, ptr %1, i64 %4
      %8 = load float, ptr %7, align 4
      %9 = fadd float %6, %8
      %10 = getelementptr inbounds nuw %TSf, ptr %2, i64 %4
      store float %9, ptr %10, align 4
      ret void
    }

    attributes #0 = { mustprogress nofree norecurse nounwind "target-cpu"="apple-m1" }

    !swift.module.flags = !{!0}
    !llvm.module.flags = !{!1}
    !0 = !{!"standard-library", i1 false}
    !1 = !{i32 1, !"wchar_size", i32 4}
    """

    func testAddLowersToValidAIRShape() throws {
        let (air, iface) = try IRToAIR.generate(ir: addIR, kernelName: "add")

        // Target facts.
        XCTAssertTrue(air.contains("target triple = \"air64_v28-apple-macosx26.0.0\""))
        XCTAssertTrue(air.contains(AIR.dataLayout))

        // Swift runtime cruft is gone.
        XCTAssertFalse(air.contains("swiftcc"))
        XCTAssertFalse(air.contains("__swift_reflection_version"))
        XCTAssertFalse(air.contains("%TSf"))
        XCTAssertFalse(air.contains("nuw"))

        // Buffers are in the device address space, params and body alike.
        XCTAssertTrue(air.contains("ptr addrspace(1) noundef \"air-buffer-no-alias\" %0"))
        XCTAssertTrue(air.contains("getelementptr inbounds float, ptr addrspace(1) %0"))
        XCTAssertTrue(air.contains("load float, ptr addrspace(1) %5"))
        XCTAssertTrue(air.contains("store float %9, ptr addrspace(1) %10"))

        // Entry-point + argument metadata contract.
        XCTAssertTrue(air.contains("!air.kernel = !{!9}"))
        XCTAssertTrue(air.contains("!9 = !{ptr @add,"))
        XCTAssertTrue(air.contains("air.thread_position_in_grid"))
        XCTAssertTrue(air.contains("!\"air.read\""))        // a, b
        XCTAssertTrue(air.contains("!\"air.read_write\""))  // out (writeonly)

        // Interface inference.
        XCTAssertEqual(iface.arguments.count, 4)
        guard case let .buffer(index0, space0, access0, _, _) = iface.arguments[0] else {
            return XCTFail("arg0 should be a buffer")
        }
        XCTAssertEqual(index0, 0)
        XCTAssertEqual(space0, .device)
        XCTAssertEqual(access0, .read)
        guard case let .buffer(_, _, access2, _, _) = iface.arguments[2] else {
            return XCTFail("arg2 should be a buffer")
        }
        XCTAssertEqual(access2, .readWrite)
        guard case .builtin(.threadPositionInGrid, _) = iface.arguments[3] else {
            return XCTFail("arg3 should be thread_position_in_grid")
        }
    }

    /// The %1 / %10 boundary bug: annotating %1 must not touch %10.
    func testAddressSpaceRewriteRespectsTokenBoundaries() throws {
        let (air, _) = try IRToAIR.generate(ir: addIR, kernelName: "add")
        // %10 is derived from device buffer %2, so it *should* be addrspace(1) —
        // but via propagation, not via a spurious %1 match.
        XCTAssertTrue(air.contains("ptr addrspace(1) %10"))
        XCTAssertFalse(air.contains("ptr addrspace(1) addrspace(1)"))
    }
}
