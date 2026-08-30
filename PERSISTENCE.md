# Cozy Bloom persistence contract

This document describes the storage contract introduced by the final schema
freeze. It is deliberately independent of Dart class names and Hive box
implementation details.

## Ownership and records

The immutable `EntryDocument` is the source model for a page. It contains the
title, title styling, A4 page specification, board authoring settings, music
metadata, and a tree of immutable canvas nodes. Child transforms are always
relative to their group. Camera zoom/pan and grid visibility are device-local
view preferences and are not page content.

Hive records use the `cozy-bloom-storage-v2` namespace in versioned boxes
(`cozyBloom.*.v2`) and explicit format and schema fields:

- `cozy-bloom.document` stores a document plus a local revision counter.
- `cozy-bloom.manifest` stores document order. Documents are authoritative if
  the manifest is interrupted or stale; missing IDs are repaired deterministically.
- `cozy-bloom.asset` stores an immutable content-addressed blob. The key and
  `id` are the lowercase SHA-256 digest of the bytes. Assets are shared by
  reference and collected only after scanning documents and checkpoints.
- `cozy-bloom.checkpoint` stores a canonical page snapshot and local recovery
  metadata.
- `cozy-bloom.view-preferences` stores camera and grid-display state per page
  and device.
- `cozy-bloom.sync` stores cloud heads in the dedicated sync-head box.

Each envelope has a required `format` discriminator and integer
`schemaVersion` (`1`). Document records add a non-negative local `revision`
and a canonical `document`; manifests contain unique ordered `documentIds`;
asset records contain `id`, `kind`, `mime`, `byteLength`, `sha256`, optional
`width`/`height`, and verified `bytes`; checkpoint records contain `id`,
`documentId`, UTC `createdAt`, and a canonical `document`; view-preference
records contain an optional camera `view` and `gridVisible`. Sync records add
an entity type, stable device/entity IDs, version vectors, mutation stamps,
document/order payloads, asset descriptors, and tombstone timestamps.

All persisted timestamps are normalized to UTC. Local revisions are never
used as cloud clocks and are never included in archive or cloud content
identity. Music records contain stable provider IDs and attribution; a
provider stream URL is resolved at playback time and is not durable content.

## Node contract

Known nodes use a stable `kind` string and `version` number. Their data is
validated before it is written. IDs are unique within a document, transforms
are finite with positive dimensions, opacity is between zero and one, and
documents are limited to 10,000 nodes and 32 group levels.

Text uses Quill Delta operations as its authoritative representation. Group
children are stored only in the tree; `groupId` and `childIds` are not storage
fields. Unknown kinds or unsupported node versions become locked opaque nodes.
Their raw JSON is retained and written back without interpretation. A future
unsupported document schema is quarantined and never rewritten by an older
build.

## Archives and cloud

`.cozyjournal` files are ZIP archives, schema version 2. `manifest.json`
contains the canonical document and asset descriptors. Binary assets are
stored under `assets/<sha256>`. Import verifies references, lengths, hashes,
MIME values, duplicate paths, and bounded resource limits before changing
local state. Version 1 JSON archives are intentionally not imported.

Drive sync uses a separate `cozy-bloom-sync-v2` namespace. It reuses the
canonical document representation, version vectors, deterministic mutation
stamps, content fingerprints, immutable assets, and indefinite tombstones.
Cloud heads are validated strictly; malformed or unsupported records are
ignored without replacing a valid local page. Camera preferences, checkpoints,
templates, and other device-local data are not synchronized.

## Compatibility policy

The application performs a one-time clean transition from the development
boxes. Existing local development data may be discarded; old cloud records
remain untouched but are outside the new namespace. The application does not
decode or import the former `Entry`/`ContentBlock` records or version-1
archives. Old local boxes are removed only after the v2 namespace initializes
successfully.

Future incompatible changes must add a new schema version and an explicit
decoder/migration. Existing decoders, discriminators, field meanings, and
golden fixtures must remain stable. Additive node features require a node
version bump so older builds preserve them as opaque data instead of silently
changing or dropping content.
