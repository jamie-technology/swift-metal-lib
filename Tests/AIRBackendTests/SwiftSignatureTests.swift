import XCTest
import GPUSwift
@testable import AIRBackend

final class SwiftSignatureTests: XCTestCase {
    func testRecoversNamesTypesAndAccess() throws {
        let src = """
        @_silgen_name("add")
        public func add(_ a: UnsafePointer<Float>,
                        _ b: UnsafePointer<Float>,
                        _ out: UnsafeMutablePointer<Float>,
                        _ gid: UInt32) {
        }
        """
        let iface = try SwiftSignature.parse(source: src, kernel: "add")
        XCTAssertEqual(iface.arguments.map(\.name), ["a", "b", "out", "gid"])
        guard case let .buffer(_, _, accA, elemA, _) = iface.arguments[0] else { return XCTFail() }
        XCTAssertEqual(accA, .read)                 // UnsafePointer -> read
        XCTAssertEqual(elemA.airName, "float")
        guard case let .buffer(_, _, accOut, _, _) = iface.arguments[2] else { return XCTFail() }
        XCTAssertEqual(accOut, .readWrite)          // UnsafeMutablePointer -> read_write
        guard case .builtin(.threadPositionInGrid, "uint", _) = iface.arguments[3] else { return XCTFail() }
    }

    func testVectorElementType() throws {
        let src = """
        @_silgen_name("v")
        public func v(_ input: UnsafePointer<SIMD4<Float>>,   // @binding(0)
                      _ gid: UInt32) {}
        """
        let iface = try SwiftSignature.parse(source: src, kernel: "v")
        guard case let .buffer(idx, _, _, elem, _) = iface.arguments[0] else { return XCTFail() }
        XCTAssertEqual(idx, 0)
        XCTAssertEqual(elem.airName, "float4")
        XCTAssertEqual(elem.size, 16)
    }

    func testMarkersDisambiguateMultipleBuiltins() throws {
        let src = """
        @_silgen_name("indices")
        public func indices(_ g: UnsafeMutablePointer<UInt32>,   // @binding(0)
                            _ l: UnsafeMutablePointer<UInt32>,    // @binding(1)
                            _ gid: UInt32,                        // @threadPositionInGrid
                            _ lid: UInt32) {                      // @threadPositionInThreadgroup
        }
        """
        let iface = try SwiftSignature.parse(source: src, kernel: "indices")
        guard case .builtin(.threadPositionInGrid, _, "gid") = iface.arguments[2],
              case .builtin(.threadPositionInThreadgroup, _, "lid") = iface.arguments[3]
        else { return XCTFail("builtins not disambiguated: \(iface.arguments)") }
    }

    func testMultipleUnmarkedScalarsIsAnError() {
        let src = """
        @_silgen_name("k")
        public func k(_ out: UnsafeMutablePointer<UInt32>, _ a: UInt32, _ b: UInt32) {}
        """
        XCTAssertThrowsError(try SwiftSignature.parse(source: src, kernel: "k"))
    }
}
