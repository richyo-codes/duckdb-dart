# Changelog

## Unreleased

- Add DuckDB 2.0 integration tests for triggers, transactional rollback,
  data-modifying CTEs, prepared parameters, nearest joins, and explicit SQL
  conversions from VARIANT. Direct VARIANT decoding is not yet exposed.
- Require new DuckDB 2.0 public APIs to be documented as experimental.

- Support DuckDB 2.0.0 through its compatible legacy C API.
- Remove the obsolete `test_api` override so tests resolve on Dart 3.10.
- Fix standalone Dart/CLI/server use without a Flutter SDK ([#41](https://github.com/TigerEyeLabs/duckdb-dart/issues/41)).
- Bundle precompiled DuckDB through build hooks for Dart and Flutter, with target
  selection, verified downloads and caching. Desktop checksums are pinned; mobile
  archives and checksum sidecars come from a versioned GitHub release.
- Use typed native asset bindings to address missing asset IDs in Windows AOT
  CLI bundles; preserve explicit dynamic-library overrides.
- Replace Flutter plugin registration and filename-based loading with native asset
  resolution; retain explicit runtime overrides and add `system`/`library_path`
  options. Linux defaults to glibc with an explicit musl option.
- Add Android arm64/x64 and iOS device/simulator source builds from a pinned
  upstream commit, shared between build hooks and CI.
- Add desktop Dart CI, CLI bundle smoke checks, and a separate mobile workflow that
  uploads binaries, SHA-256 checksums and provenance to a draft release.
- Mobile binary mode requires publishing the first native release; until then use
  source mode or a local library. DuckDB-Wasm remains separately configured.
- Update legacy native build recipes and the iOS framework patch for DuckDB 2.0.
- Upgrade `code_assets` to ^2.1.0, `ffigen` to ^23.0.0, and `lints` to ^6.1.0.

## 1.4.4

- upgrade duckdb binaries to 1.4.2
- introduce the JsonValue for Json columns

## 1.4.3

- Add web folders

## 1.4.1

- Upgrade to DuckDB 1.4.1
- Add JSON column support
- Add web/WASM support for DuckDB
- Update platform-specific build configurations
- Update test suite with new type tests
- Bump Flutter and dependency versions

## 1.3.2

- bump duckdb version

## 1.2.0
- ✨ Added Web support via DuckDB WASM

## 1.1.3
- ✨ Added support for all DuckDB datatypes
- ✨ Added streaming query results
- ⚡️ Improved query performance with faster datachunk indexing
- 🔧 Full Value support for PreparedStatements
- 💡 Enhanced vector and value classes with Dart generics
- 📦 Reduced Android binary size by removing unused symbols

## 1.1.0
- ✨ Added support for cancellable queries via DuckDB's pending results

## 1.0.3
- 📝 Minor documentation updates

## 1.0.2
- 🔧 Auto-download DuckDB builds during build process for Android/Windows/Linux/macOS

## 1.0.1
- 🐛 Fixed pub.dev publishing issues

## 1.0.0
- 🎉 Initial release
