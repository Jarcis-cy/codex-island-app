import XCTest
@testable import Codex_Island

final class AnyCodableTests: XCTestCase {
    func testEncodingUnsupportedValueIncludesHelpfulTypeContext() {
        let value = AnyCodable(Date())
        let encoder = JSONEncoder()

        XCTAssertThrowsError(try encoder.encode(value)) { error in
            guard case EncodingError.invalidValue(_, let context) = error else {
                return XCTFail("Expected invalidValue, got \(error)")
            }
            XCTAssertTrue(context.debugDescription.contains("Cannot encode value"))
        }
    }

    func testDecodePreservesNestedObjects() throws {
        let data = Data(#"{"outer":{"value":1,"flag":true},"items":["a","b"]}"#.utf8)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)

        let object = try XCTUnwrap(decoded.value as? [String: Any])
        let outer = try XCTUnwrap(object["outer"] as? [String: Any])
        XCTAssertEqual(outer["value"] as? Int, 1)
        XCTAssertEqual(outer["flag"] as? Bool, true)
        XCTAssertEqual(object["items"] as? [String], ["a", "b"])
    }
}
