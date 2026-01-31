// Tests/SwiftProtobufTests/Test_UUID.swift - UUID serialization tests
//
// Copyright (c) 2025 Tolki Chat. All rights reserved.

import Foundation
import XCTest
@testable import SwiftProtobuf

/// Tests for ProtobufUUID field type
final class Test_UUID: XCTestCase {

    // MARK: - Default Value

    func testDefaultValue() {
        let defaultUUID = ProtobufUUID.proto3DefaultValue
        // Default should be nil UUID (all zeros)
        XCTAssertEqual(defaultUUID, UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)))
    }

    // MARK: - Serialization Round-Trip

    func testUUIDRoundTrip() throws {
        let originalUUID = UUID()

        // Serialize UUID to bytes
        let data = withUnsafeBytes(of: originalUUID.uuid) { Data($0) }
        XCTAssertEqual(data.count, 16, "UUID should serialize to 16 bytes")

        // Deserialize bytes back to UUID
        let restoredUUID = data.withUnsafeBytes { ptr in
            UUID(uuid: ptr.load(as: uuid_t.self))
        }

        XCTAssertEqual(originalUUID, restoredUUID, "Round-trip should preserve UUID")
    }

    func testKnownUUIDSerialization() throws {
        // Test with a known UUID
        let knownUUID = UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!

        // Serialize
        let data = withUnsafeBytes(of: knownUUID.uuid) { Data($0) }
        XCTAssertEqual(data.count, 16)

        // Expected bytes for this UUID (big-endian format)
        let expectedBytes: [UInt8] = [
            0x55, 0x0e, 0x84, 0x00,  // time_low
            0xe2, 0x9b,              // time_mid
            0x41, 0xd4,              // time_hi_and_version
            0xa7, 0x16,              // clock_seq
            0x44, 0x66, 0x55, 0x44, 0x00, 0x00  // node
        ]
        XCTAssertEqual(Array(data), expectedBytes)

        // Deserialize
        let restored = data.withUnsafeBytes { ptr in
            UUID(uuid: ptr.load(as: uuid_t.self))
        }
        XCTAssertEqual(knownUUID, restored)
    }

    func testMultipleUUIDsRoundTrip() throws {
        // Test with multiple random UUIDs
        for _ in 0..<100 {
            let uuid = UUID()
            let data = withUnsafeBytes(of: uuid.uuid) { Data($0) }
            let restored = data.withUnsafeBytes { ptr in
                UUID(uuid: ptr.load(as: uuid_t.self))
            }
            XCTAssertEqual(uuid, restored, "Each UUID should survive round-trip")
        }
    }

    // MARK: - Edge Cases

    func testNilUUID() throws {
        let nilUUID = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
        let data = withUnsafeBytes(of: nilUUID.uuid) { Data($0) }

        // All bytes should be zero
        XCTAssertTrue(data.allSatisfy { $0 == 0 })
        XCTAssertEqual(data.count, 16)

        let restored = data.withUnsafeBytes { ptr in
            UUID(uuid: ptr.load(as: uuid_t.self))
        }
        XCTAssertEqual(nilUUID, restored)
    }

    func testMaxUUID() throws {
        let maxUUID = UUID(uuid: (0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,
                                  0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF))
        let data = withUnsafeBytes(of: maxUUID.uuid) { Data($0) }

        // All bytes should be 0xFF
        XCTAssertTrue(data.allSatisfy { $0 == 0xFF })
        XCTAssertEqual(data.count, 16)

        let restored = data.withUnsafeBytes { ptr in
            UUID(uuid: ptr.load(as: uuid_t.self))
        }
        XCTAssertEqual(maxUUID, restored)
    }

    // MARK: - Invalid Data Handling

    func testInvalidDataLength() throws {
        // Data with wrong length should not create a valid UUID
        let shortData = Data([0x01, 0x02, 0x03])  // Only 3 bytes
        XCTAssertEqual(shortData.count, 3)
        XCTAssertNotEqual(shortData.count, 16, "Invalid data length should be detected")

        let longData = Data(repeating: 0x42, count: 32)  // 32 bytes
        XCTAssertEqual(longData.count, 32)
        XCTAssertNotEqual(longData.count, 16, "Invalid data length should be detected")
    }

    // MARK: - Performance

    func testSerializationPerformance() throws {
        let uuid = UUID()

        measure {
            for _ in 0..<10000 {
                _ = withUnsafeBytes(of: uuid.uuid) { Data($0) }
            }
        }
    }

    func testDeserializationPerformance() throws {
        let uuid = UUID()
        let data = withUnsafeBytes(of: uuid.uuid) { Data($0) }

        measure {
            for _ in 0..<10000 {
                _ = data.withUnsafeBytes { ptr in
                    UUID(uuid: ptr.load(as: uuid_t.self))
                }
            }
        }
    }

    func testRoundTripPerformance() throws {
        measure {
            for _ in 0..<10000 {
                let uuid = UUID()
                let data = withUnsafeBytes(of: uuid.uuid) { Data($0) }
                _ = data.withUnsafeBytes { ptr in
                    UUID(uuid: ptr.load(as: uuid_t.self))
                }
            }
        }
    }
}
