# UUID Support for Swift Protobuf — Plan

## Context

We have a fork of swift-protobuf where we're adding native UUID support. The goal: proto fields annotated with `[(uuid) = "v4"]` should generate Swift `UUID` type instead of `Data`, so we can use protobuf structs directly in business logic (comparisons, Hashable, etc.) without manual transformations.

### Proto Example
```protobuf
// tolki/options.proto
extend google.protobuf.FieldOptions {
  optional string uuid = 50001;
}

// usage:
message Message {
  bytes id = 1 [(uuid) = "v4"];
  bytes chat_id = 2 [(uuid) = "v4"];
  optional bytes server_id = 13 [(uuid) = "v4"];
  repeated bytes ids = 1 [(uuid) = "v4"];
}
```

### Reference: Rust prost implementation
In our prost fork (`/src/prost`), UUID support works via:
- `BytesAdapter` trait with `uuid::Uuid` implementation (16 bytes, fixed-size)
- `BytesTy::Uuid` variant in derive macro
- `uuid::Uuid::nil()` as default value
- Feature-gated `uuid` dependency

### Current State (swift-protobuf)
Two commits already made:
1. `415e1c46` — `ProtobufUUID` field type in runtime + `hasUuidOption` detection in codegen
2. `04014716` — Unit tests for UUID serialization

**What's done:**
- `ProtobufUUID` struct in `FieldTypes.swift` (encode/decode UUID as 16-byte Data)
- `hasUuidOption` property on `FieldDescriptor` (3-tier detection: extension values → uninterpreted options → raw unknown fields)
- `swiftType()` returns `"UUID"` for UUID bytes fields
- `swiftDefaultValue()` returns `"UUID()"` for UUID bytes fields
- `traitsType()` returns `"ProtobufUUID"` for UUID bytes fields
- Basic unit tests for ProtobufUUID round-trip

---

## Problems Found (Bugs in Current Implementation)

### BUG 1: CRITICAL — Traverse generates `.isEmpty` for UUID
**File:** `Sources/protoc-gen-swift/MessageFieldGenerator.swift:217-231`

For proto3 non-optional fields, the codegen generates:
```swift
if !id.isEmpty { // COMPILE ERROR: UUID has no .isEmpty
    try visitor.visitSingularBytesField(value: id, fieldNumber: 1)
}
```

**Fix:** For UUID bytes, generate comparison with nil UUID instead:
```swift
if id != UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)) {
    try visitor.visitSingularBytesField(value: id, fieldNumber: 1)
}
```

### BUG 2: CRITICAL — Decoder doesn't use ProtobufUUID traits for non-map fields
**File:** `Sources/protoc-gen-swift/MessageFieldGenerator.swift:174-186`

For non-map fields, `traitsArg` is empty — the generated decode call uses the generic `decodeSingularBytesField` which expects `Data`, not `UUID`:
```swift
// Generated (WRONG):
try decoder.decodeSingularBytesField(value: &_id)
// _id is UUID?, but decoder expects Data?
```

**Fix:** For UUID fields, the decoder must use the traits-based method:
```swift
try decoder.decodeSingularField(fieldType: SwiftProtobuf.ProtobufUUID.self, value: &_id)
```

### BUG 3: HIGH — Foundation import may be missing
**File:** `Sources/protoc-gen-swift/Descriptor+Extensions.swift` (FileDescriptor + Descriptor extensions)

`needsFoundationImport` checks for bytes fields → returns true → imports Foundation. Currently this works because `type == .bytes` catches UUID fields too. But if someone refactors to exclude UUID fields from this check, Foundation won't be imported.

**Status:** Currently works by accident, but fragile. Should add explicit UUID check.

### BUG 4: MEDIUM — Traverse visitor call uses wrong method for UUID
**File:** `Sources/protoc-gen-swift/MessageFieldGenerator.swift`

The traverse generates:
```swift
try visitor.visitSingularBytesField(value: v, fieldNumber: N)
```

But `v` is `UUID`, and `visitSingularBytesField` expects `Data`. Need to use traits-based visitor or convert UUID→Data inline.

---

## Implementation Plan

### Phase 1: Fix Runtime Library (ProtobufUUID)

**File:** `Sources/SwiftProtobuf/FieldTypes.swift`

1. Verify `ProtobufUUID` works with the decoder/visitor protocol correctly
2. Add conformance to `_ProtoNameProviding` if needed
3. Make sure `ProtobufUUID` is compatible with the `decodeSingular`/`visitSingular` call patterns used by the code generator

### Phase 2: Fix Code Generator (protoc-gen-swift)

**File:** `Sources/protoc-gen-swift/MessageFieldGenerator.swift`

#### 2a. Fix decode generation
In `generateDecodeFieldCase()`:
- When field is bytes + hasUuidOption → generate traits-based decode call
- For singular: `try decoder.decodeSingularField(fieldType: ProtobufUUID.self, value: &_storage)`
- For repeated: `try decoder.decodeRepeatedField(fieldType: ProtobufUUID.self, value: &_storage)`

#### 2b. Fix traverse generation
In `generateTraverse()`:
- When field is bytes + hasUuidOption, don't use `.isEmpty`
- For proto3 non-optional: compare with `ProtobufUUID.proto3DefaultValue` equivalent
- For traverse visitor: use traits-based `visitSingularField(fieldType: ProtobufUUID.self, value: v, fieldNumber: N)`

#### 2c. Fix oneof handling
**File:** `Sources/protoc-gen-swift/OneofGenerator.swift`
- Verify UUID fields in oneof decode correctly
- Verify UUID fields in oneof traverse correctly
- `protoGenericType` returns "Bytes" — verify this works with traits approach

**File:** `Sources/protoc-gen-swift/Descriptor+Extensions.swift`

#### 2d. Harden Foundation import
- Add explicit comment documenting that UUID also needs Foundation
- Verify `needsFoundationImport` returns true for UUID-only protos

### Phase 3: Add Decoder/Visitor Protocol Methods

**Files:** Various in `Sources/SwiftProtobuf/`

The decoder and visitor protocols may need new methods or the existing generic ones must accept UUID. Options:

**Option A (Minimal):** Use existing generic `decodeSingularField(fieldType:value:)` / `visitSingularField(fieldType:value:)` — these accept any `FieldType` conformer. **This is the preferred approach.**

**Option B (New methods):** Add `decodeSingularUUIDField` / `visitSingularUUIDField` to the decoder/visitor protocols. More invasive but more explicit.

**Recommendation:** Option A — use the generic traits-based methods that already exist.

### Phase 4: End-to-End Testing

1. **Create test .proto file** with UUID fields covering all scenarios:
   ```protobuf
   message TestUUID {
     bytes simple_id = 1 [(uuid) = "v4"];           // proto3 non-optional
     optional bytes opt_id = 2 [(uuid) = "v4"];      // proto3 optional
     repeated bytes ids = 3 [(uuid) = "v4"];          // repeated
   }

   message TestUUIDOneof {
     oneof value {
       bytes uuid_field = 1 [(uuid) = "v4"];
       string text_field = 2;
     }
   }
   ```

2. **Generate Swift code** from test proto using our modified protoc-gen-swift

3. **Write integration tests:**
   - Create message with UUID fields, serialize, deserialize, compare
   - Test all field variants: singular, optional, repeated, oneof
   - Test JSON serialization (UUID as base64? or string?)
   - Test text format serialization
   - Test default values
   - Test equality/hashability of generated message types
   - Cross-test: serialize in Swift, deserialize in Rust (prost), verify round-trip

4. **Test with real tolki protos:**
   - Generate Swift code from `/src/tolki/.proto/api/tolki/message/v1/message.proto`
   - Verify all UUID fields (Message.id, Message.chat_id, etc.) are `UUID` type
   - Verify the generated code compiles and works

### Phase 5: JSON / TextFormat Handling

UUID fields need special handling in JSON and TextFormat:

**JSON:**
- Standard protobuf JSON encodes bytes as base64
- For UUID fields, we may want to encode as UUID string (`"550e8400-e29b-41d4-a716-446655440000"`)
- **Decision needed:** Keep base64 (wire-compatible) or UUID string (human-readable)?
- Recommendation: UUID string in JSON for interoperability with other systems

**TextFormat:**
- Similarly, UUID hex string representation is more useful than raw bytes

### Phase 6: Hashable / Equatable / Comparable

Verify that generated message types with UUID fields:
- Conform to `Equatable` (UUID is already Equatable)
- Conform to `Hashable` if all fields support it (UUID is Hashable)
- Can be used as dictionary keys or in Sets

---

## File Change Summary

| File | Changes |
|------|---------|
| `Sources/SwiftProtobuf/FieldTypes.swift` | Verify ProtobufUUID, possibly add methods |
| `Sources/protoc-gen-swift/MessageFieldGenerator.swift` | Fix decode + traverse for UUID |
| `Sources/protoc-gen-swift/OneofGenerator.swift` | Fix decode + traverse for UUID in oneof |
| `Sources/protoc-gen-swift/Descriptor+Extensions.swift` | Harden Foundation import check |
| `Sources/SwiftProtobuf/JSONDecoder.swift` | UUID JSON decode (string format) |
| `Sources/SwiftProtobuf/JSONEncoder.swift` | UUID JSON encode (string format) |
| `Sources/SwiftProtobuf/TextFormatDecoder.swift` | UUID text format decode |
| `Sources/SwiftProtobuf/TextFormatEncoder.swift` | UUID text format encode |
| `Tests/SwiftProtobufTests/Test_UUID.swift` | Expand tests |
| `Protos/` | Add test .proto with UUID fields |

---

## Execution Order

```
Phase 1 (Runtime)
  └─ Verify/fix ProtobufUUID in FieldTypes.swift

Phase 2 (Codegen) — MAIN WORK
  ├─ 2a. Fix MessageFieldGenerator decode
  ├─ 2b. Fix MessageFieldGenerator traverse
  ├─ 2c. Fix OneofGenerator
  └─ 2d. Harden imports

Phase 3 (Protocol methods)
  └─ Ensure decoder/visitor generics work with UUID

Phase 4 (Testing)
  ├─ Test proto files
  ├─ Generate code
  └─ Integration tests

Phase 5 (JSON/TextFormat) — OPTIONAL, can defer
  ├─ JSON UUID string encoding
  └─ TextFormat UUID encoding

Phase 6 (Verification)
  ├─ Hashable/Equatable conformance
  └─ Real proto (tolki) end-to-end test
```

---

## Open Questions

1. **JSON encoding:** Should UUID be JSON-encoded as base64 (standard bytes behavior) or as UUID string? UUID string is more interoperable but breaks bytes compatibility.

2. **Nil UUID handling:** Should `UUID()` (all zeros) be treated as "empty" (not serialized in proto3) or should only `nil` mean "not set"? Current approach: nil UUID = proto3 default = not serialized.

3. **Proto2 support:** Do we need UUID support for proto2 files? Current `hasUuidOption` checks `type == .bytes` which works for both proto2 and proto3.

4. **Map support:** Do we need `map<string, bytes>` where value has UUID option? Low priority but worth considering.
