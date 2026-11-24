# Export format

Status: Draft
Version: 0.2

This document defines the Archive: the one file an Export writes, holding every Book on a device with its Entries and Images, so that the user keeps a copy outside Kronoer and an Import can bring it back. Unlike everything in [Entry format](entry-format.md), the Archive is **not encrypted**. The reference implementation is `core/src/store/export.rs`.

## Terminology

- **Export**: writing every Book on a device into one Archive.
- **Import**: reading an Archive back into Kronoer. This document says what an importer can rely on and what it must check and refuse; how it merges is out of scope. The reference implementation is `core/src/store/import.rs`.
- **Archive**: the ZIP file one Export writes.
- **Writer** and **reader**: an implementation that writes an Archive, and one that reads it.

Entry, Book, Image, Cover, Description, Entry date, Starred Entry, Locked Book, and Text style mean what they mean in [Entry format](entry-format.md#terminology). The Trash is where the user's deleted Books and Entries wait before they are gone for good.

## What an Archive holds

An Archive holds every Book that is not in the Trash, Locked Books included, and every Entry that is not in the Trash, with every Image and Cover they use. It also holds which of those Entries are starred and which of those Books are locked.

It holds nothing else: no keys, nothing from the Trash, and no setting of the device or the app (such as App lock, the Writing reminder, pinned Books, or which Books the Timeline shows).

## Archive

An Archive is a ZIP file ([APPNOTE](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT)). Its file name is not part of the format; Kronoer suggests `kronoer-YYYY-MM-DD.zip`, the local day it is made.

It holds these files, with these exact names:

| Name                  | Compression       | Content                                     |
| --------------------- | ----------------- | ------------------------------------------- |
| `README.txt`          | Deflate or stored | A note for a person who opens the Archive.  |
| `kronoer.json`        | Deflate or stored | Every Book and Entry. See [kronoer.json](#kronoerjson). |
| `images/<id>.jpg`     | Stored or Deflate | One Image or Cover, the full variant, as JPEG. `<id>` is its Image ID in text form. |

A writer:

- MUST write `kronoer.json`, and one `images/<id>.jpg` for every Image ID that `kronoer.json` names, and MUST NOT write two files with the same name.
- MUST write names in UTF-8, with `/` as the separator, and no directory entries are needed.
- SHOULD write `README.txt` first, then `kronoer.json`, then the images, so that a reader streaming the ZIP sees the data before the Images it names. Kronoer writes the ZIP as a stream (with data descriptors), so the file never needs to seek.
- SHOULD store JPEG files without compression: it does not make them smaller.

A reader:

- MUST find files by name, not by their order.
- MUST ignore files it does not know, so later versions can add some.
- MUST treat an Archive without `kronoer.json`, or one whose `kronoer.json` names an Image with no file, as damaged.

The ZIP's file times are the Export's time in UTC. They carry no meaning; a reader uses `exported_at`.

## kronoer.json

`kronoer.json` is one JSON object ([RFC 8259](https://www.rfc-editor.org/rfc/rfc8259)) in UTF-8 without a byte order mark. Its structure, in CDDL ([RFC 8610](https://www.rfc-editor.org/rfc/rfc8610)) for JSON:

```cddl
archive = {
  format: "kronoer-archive",
  format_version: uint,             ; 1 in this version
  exported_at: utc-time,
  books: [* book],
  locked_book_ids: [* id-text],
  starred_entry_ids: [* id-text],
  entries: [* entry],
}

book = {
  id: id-text,
  name: tstr,
  description: tstr,                ; "" when the Book has none
  cover_image_id: id-text / null,   ; null when the Book has no Cover
}

entry = {
  id: id-text,
  book_id: id-text,
  entry_date: tstr,                 ; an Entry date, as in entry-format.md
  text: tstr,                       ; may be empty, and may hold Text styles
  image_ids: [* id-text],           ; in the order they are shown
  created_at: utc-time,
  updated_at: utc-time,
}

id-text = tstr .regexp "[0-9a-f]{32}"
utc-time = tstr .regexp "[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}Z"
```

- `format` tells a Kronoer Archive from any other JSON file. A reader MUST reject a file whose `format` is not `kronoer-archive`.
- `format_version` is the version of this structure. A reader MUST check it before reading the rest, and MUST reject an Archive whose `format_version` it does not know, with a way for the user to tell that the Archive is newer than the app (Kronoer: "made by a newer version of Kronoer").
- `id-text` is an identifier in text form: 32 lowercase hexadecimal digits ([Identifiers](entry-format.md#identifiers)). Book IDs, Entry IDs, and Image IDs are the ones the device stores, so an Import can tell an Entry it already has from a new one.
- `utc-time` is a [time](entry-format.md#times) written in UTC as RFC 3339 with exactly three fractional digits and `Z`: `2026-11-24T04:30:00.000Z`. `exported_at` is when the Export started; `created_at` and `updated_at` are when the Entry was first written and last changed.
- `entry_date` keeps its offset and MUST be a valid [Entry date](entry-format.md#entry-date). A reader MUST NOT convert it to another time zone.
- `text` is the Entry's text as written, with Text style marks left in it as the [Text styles](entry-format.md#text-styles) section describes.
- Every `book_id` names a Book in `books`. Every ID in `locked_book_ids` names a Book in `books`, and every ID in `starred_entry_ids` an Entry in `entries`. No list holds an ID twice, and no Image ID is the Cover of two Books or appears in two Entries.

A writer:

- MUST write the keys of `archive` in the order shown, so a reader streaming the file knows the Books, locks, and stars before the first Entry. Inside `book` and `entry` the order does not matter.
- SHOULD write `books` with the most recently active first, and `entries`, `starred_entry_ids` oldest first (by Entry date, then `created_at`, then ID).

A reader:

- MUST ignore keys it does not know, in any object, so later minor changes can add some without a new `format_version`.
- MUST treat a broken reference (a `book_id`, a locked or starred ID, or an Image ID with no match) as damage.

## Reading an Archive

A reader checks the whole Archive before it changes anything, and takes it whole or not at all: from an Archive that fails a check it imports nothing, and it tells the user which of these three it is.

| Refusal | When |
| ------- | ---- |
| Damaged | The file is not a ZIP, or its ZIP does not end properly, or a file's data does not match its CRC-32. There is no `kronoer.json`, or it is not JSON, or its `format` is not `kronoer-archive`, or its `format_version` is not a known one and not newer. A key the structure needs is missing or of the wrong type. An `id-text`, `utc-time`, or Entry date is not valid. A list holds an ID twice, or a Book or Entry is listed twice. A reference is broken, an Image ID is used twice, or an Image ID has no `images/<id>.jpg`. |
| Newer | `format_version` is greater than any the reader knows (Kronoer: "made by a newer version of Kronoer"). |
| Image | An Image the reader would import is not a JPEG whose segments hold together and that decodes, or its frame is larger than 2048 pixels on a side. |

A reader:

- MUST read `format` and `format_version` on their own before the rest, so that an Archive whose later structure differs is told as newer, not as damaged.
- MUST find the file of every Image `kronoer.json` names. It MUST check every Image it imports; it MAY leave unchecked the Images of Books and Entries it does not import, such as those the device already has.
- MUST limit what it reads to what fits, and treat a file larger than the ZIP says as damaged. Kronoer reads at most 256 MiB of `kronoer.json` and 32 MiB of each image file.
- MUST NOT keep a JPEG's metadata. Before storing an Image it drops these segments without encoding the picture again: APP1 (EXIF and XMP), APP2 unless it is an ICC profile (`ICC_PROFILE\0`), APP3 to APP13 (IPTC among them), APP15, COM, and any bytes after EOI. It keeps APP0 (JFIF), the ICC profile, and APP14 (Adobe), which say how to read the colors, and every other segment.
- SHOULD make each Image's thumbnail from the full Image. The Archive holds none.
- MUST seal what it imports with the device's own keys, like anything new. The Archive holds no key, and a reader asks for none: whoever has the file can read it without Kronoer.

## Example

An Archive with one Book, locked, and its one starred Entry with one Image:

```text
README.txt
kronoer.json
images/5a0c6b2e9d1f4e8a8c3b7d6e1f2a4b9c.jpg
```

`kronoer.json`:

```json
{
  "format": "kronoer-archive",
  "format_version": 1,
  "exported_at": "2026-11-24T12:40:00.000Z",
  "books": [
    {"id":"0f4b8e2a7c1d4f6b9a3e5c7d2b1a8f6e","name":"Kebun","description":"Catatan kebun belakang.","cover_image_id":null}
  ],
  "locked_book_ids": ["0f4b8e2a7c1d4f6b9a3e5c7d2b1a8f6e"],
  "starred_entry_ids": ["9e1d3c5b7a2f4e6d8c0b1a3f5e7d9c2b"],
  "entries": [
    {"id":"9e1d3c5b7a2f4e6d8c0b1a3f5e7d9c2b","book_id":"0f4b8e2a7c1d4f6b9a3e5c7d2b1a8f6e","entry_date":"2026-11-17T08:00:00+07:00","text":"Tomat mulai *merah*.","image_ids":["5a0c6b2e9d1f4e8a8c3b7d6e1f2a4b9c"],"created_at":"2026-11-17T01:00:12.345Z","updated_at":"2026-11-17T01:05:00.000Z"}
  ]
}
```

Kronoer writes one Book or Entry per line, as here; a reader MUST NOT depend on white space.

## Security considerations

- **No encryption.** Anyone who holds an Archive can read every Entry, Image, and Book name in it, those of Locked Books included. A Locked Book is listed as locked, but nothing in the Archive enforces it. Kronoer warns before an Export and asks for the device's own lock first when there is a Locked Book; keeping the file safe is the user's.
- **No keys.** An Archive holds no key of any kind, so it never helps to open the device's store or anything synced.
- **No integrity.** Nothing in the Archive proves who wrote it or that it is unchanged. A reader MUST treat every value as untrusted input: check every ID, Entry date, and reference, limit what it reads to what fits, and never trust a file name beyond `images/<id>.jpg` with a valid ID (no other path, no `..`).
- **Unfinished files.** A writer that fails or is stopped MUST delete what it wrote, so no partial Archive is left looking like a whole one. A reader still MUST treat an Archive whose ZIP does not end properly as damaged.

## Changes

- 0.2 (2026-11-24): What a reader must check and refuse, how it drops an Image's metadata, and that it makes its own thumbnails.
- 0.1 (2026-11-24): First draft. The ZIP layout, `kronoer.json` with `format_version` 1, and the example.
