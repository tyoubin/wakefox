import XCTest
import AppKit
@testable import WakeFox

final class ShortcutMapperTests: XCTestCase {
    func testFirstNineItemsUsePlainDigits() {
        let first = ShortcutMapper.shortcut(for: 0)
        let ninth = ShortcutMapper.shortcut(for: 8)

        XCTAssertEqual(first?.keyEquivalent, "1")
        XCTAssertEqual(first?.modifiers, [.command])
        XCTAssertEqual(ninth?.keyEquivalent, "9")
        XCTAssertEqual(ninth?.modifiers, [.command])
    }

    func testTenthItemUsesZeroKey() {
        let tenth = ShortcutMapper.shortcut(for: 9)
        XCTAssertEqual(tenth?.keyEquivalent, "0")
        XCTAssertEqual(tenth?.modifiers, [.command])
    }

    func testItemsBeyondTenUseModifierLayers() {
        let eleventh = ShortcutMapper.shortcut(for: 10)
        XCTAssertEqual(eleventh?.keyEquivalent, "1")
        XCTAssertEqual(eleventh?.modifiers, [.command, .option])

        let twentyFirst = ShortcutMapper.shortcut(for: 20)
        XCTAssertEqual(twentyFirst?.keyEquivalent, "1")
        XCTAssertEqual(twentyFirst?.modifiers, [.command, .control])
    }

    func testOutOfRangeReturnsNil() {
        XCTAssertNil(ShortcutMapper.shortcut(for: -1))
        XCTAssertNil(ShortcutMapper.shortcut(for: 50))
    }
}
