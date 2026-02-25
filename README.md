# Swift Protobuf (Tolki Fork)

Fork of [apple/swift-protobuf](https://github.com/apple/swift-protobuf) with native UUID support.

## What's different

Proto `bytes` fields annotated with `[(uuid)]` option generate Swift `UUID` type instead of `Data`:

```protobuf
import "options.proto";

message Message {
  bytes id = 1 [(uuid) = "v4"];           // -> var id: UUID
  optional bytes ref = 2 [(uuid) = "v4"]; // -> var ref: UUID  (with hasRef/clearRef)
  repeated bytes ids = 3 [(uuid) = "v4"]; // -> var ids: [UUID]
  bytes payload = 4;                       // -> var payload: Data  (unchanged)
}
```

UUID fields are Hashable, Equatable, and serialize as 16-byte big-endian — fully wire-compatible with standard protobuf bytes.

## Usage

In `Package.swift`, point to this fork:

```swift
dependencies: [
    .package(url: "https://github.com/tolkichat/swift-protobuf.git", branch: "main"),
]
```

Define the custom field option in your proto:

```protobuf
// options.proto
syntax = "proto3";
import "google/protobuf/descriptor.proto";

extend google.protobuf.FieldOptions {
  optional string uuid = 50001;
}
```

Generate Swift code with `protoc-gen-swift` from this fork.

## Original documentation

See the upstream repo for full documentation: https://github.com/apple/swift-protobuf
