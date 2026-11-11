import XCTest
@testable import RemindMe

final class DeliveryLogTests: XCTestCase {
    func testNewestFirstAndCapped() {
        var log = DeliveryLog()
        for i in 0..<(DeliveryLog.limit + 3) {
            log.add(.fired, title: "r\(i)", at: Date(timeIntervalSince1970: TimeInterval(i)))
        }
        XCTAssertEqual(log.entries.count, DeliveryLog.limit)
        XCTAssertEqual(log.entries.first?.title, "r\(DeliveryLog.limit + 2)")
    }

    func testEachStepHasAPlainLabel() {
        let labels = [DeliveryLog.Step.fired, .shown, .acknowledged, .missed, .unfinished].map(\.label)
        XCTAssertEqual(labels, ["Due", "Shown", "Answered", "Missed", "Unfinished"])
    }

    func testEntryKeepsStepAndDetail() {
        var log = DeliveryLog()
        log.add(.missed, title: "Pay rent", at: .now, detail: "Came due while asleep")
        XCTAssertEqual(log.entries.first?.step, .missed)
        XCTAssertEqual(log.entries.first?.detail, "Came due while asleep")
    }
}
