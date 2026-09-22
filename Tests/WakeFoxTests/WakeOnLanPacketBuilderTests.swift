import XCTest
@testable import WakeFox

final class WakeOnLanPacketBuilderTests: XCTestCase {
    func testBuildPacketWithValidMacAddress() throws {
        let packet = try WakeOnLanPacketBuilder.buildPacket(macAddress: "01:23:45:67:89:AB")
        XCTAssertEqual(packet.count, 102)

        let bytes = [UInt8](packet)
        XCTAssertEqual(Array(bytes[0..<6]), Array(repeating: 0xFF, count: 6))

        let expectedMac: [UInt8] = [0x01, 0x23, 0x45, 0x67, 0x89, 0xAB]
        for i in 0..<16 {
            let start = 6 + (i * 6)
            XCTAssertEqual(Array(bytes[start..<(start + 6)]), expectedMac)
        }
    }

    func testBuildPacketWithInvalidMacAddressThrows() {
        XCTAssertThrowsError(try WakeOnLanPacketBuilder.buildPacket(macAddress: "01:23:45")) { error in
            guard case WakeOnLanError.invalidMacAddress = error else {
                XCTFail("Expected invalidMacAddress error, got \(error)")
                return
            }
        }
    }

    func testBuildPacketWithDashSeparatedMacAddress() throws {
        let packet = try WakeOnLanPacketBuilder.buildPacket(macAddress: "AA-BB-CC-DD-EE-FF")
        XCTAssertEqual(packet.count, 102)
    }
}
