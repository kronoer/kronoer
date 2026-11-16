# Kronoer specifications

This folder defines the formats and protocols that Kronoer stores and sends, precisely enough to build a compatible implementation without reading the code.

## Scope

In scope:

- The encrypted Entry format, used both on the device and on the server
- The export archive
- The sync and sharing protocol (V1)

Out of scope: app behavior, UI, and anything that does not cross a storage or network boundary.

The reference implementation is `core/`. If `core/` and a document here disagree, one of them has a bug; fix it in the same pull request.

## Requirement keywords

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in these documents are to be interpreted as described in BCP 14 ([RFC 2119](https://www.rfc-editor.org/rfc/rfc2119), [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174)) when, and only when, they appear in all capitals, as shown here.

## Writing a document

- One document per format or protocol, named in kebab-case, for example `entry-format.md`.
- Each document starts with this header:

  ```markdown
  # Entry format

  Status: Draft
  Version: 0.1
  ```

- **Status** is `Draft` while it may still change incompatibly, and `Stable` once data written with it must stay readable.
- **Version** is `major.minor`. Raise the minor version for clarifications and compatible additions, and the major version for incompatible changes. A Stable document never changes incompatibly; write a new major version instead.
- The document version describes the text. Data on disk or on the wire carries its own format version field, defined in the document.
- Each document has a **Terminology** section that defines the terms it uses, such as Entry, Book, and Book key. Use one term per concept, the same one the code uses.
- Each document ends with a **Changes** section listing its versions.

## Test vectors

Every format with cryptography or a byte-exact encoding has test vectors in [`test-vectors/`](test-vectors/). An implementation is compatible only if it reproduces them.

## License

Dual-licensed under [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE), at your option.