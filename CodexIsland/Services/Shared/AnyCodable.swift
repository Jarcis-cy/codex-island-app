//
//  AnyCodable.swift
//  CodexIsland
//
//  Shared Codable wrapper for heterogenous JSON values.
//

import Foundation

nonisolated struct AnyCodable: Codable, @unchecked Sendable {
    nonisolated(unsafe) let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        var attemptedTypes: [String] = []

        func decodeValue<T>(_ type: T.Type, name: String, using operation: () throws -> T?) rethrows -> T? {
            attemptedTypes.append(name)
            return try operation()
        }

        if container.decodeNil() {
            value = NSNull()
        } else if let bool = decodeValue(Bool.self, name: "Bool", using: { try? container.decode(Bool.self) }) {
            value = bool
        } else if let int = decodeValue(Int.self, name: "Int", using: { try? container.decode(Int.self) }) {
            value = int
        } else if let double = decodeValue(Double.self, name: "Double", using: { try? container.decode(Double.self) }) {
            value = double
        } else if let string = decodeValue(String.self, name: "String", using: { try? container.decode(String.self) }) {
            value = string
        } else if let array = decodeValue([AnyCodable].self, name: "[AnyCodable]", using: { try? container.decode([AnyCodable].self) }) {
            value = array.map(\.value)
        } else if let dict = decodeValue([String: AnyCodable].self, name: "[String: AnyCodable]", using: { try? container.decode([String: AnyCodable].self) }) {
            value = dict.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode value as any supported JSON type. Attempted: \(attemptedTypes.joined(separator: ", "))"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map(AnyCodable.init))
        case let dict as [String: Any]:
            try container.encode(dict.mapValues(AnyCodable.init))
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(codingPath: [], debugDescription: "Cannot encode value")
            )
        }
    }
}
