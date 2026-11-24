//! Export: every Book not in the Trash, with its Entries and Images, written into one
//! unencrypted Archive, as `spec/export-format.md` defines it.
//!
//! The Archive is a ZIP written as a stream, so the file it goes to does not need to seek: a file
//! the user picked can be on a provider that only takes bytes in order. `kronoer.json` comes
//! first, one Entry at a time, then each Image, so neither the text nor the Images of every
//! Entry are held at once. The store is locked for one Entry or Image at a time, not for the
//! whole Export.

use std::io::{self, BufWriter, Write};

use serde::Serialize;
use zip::write::SimpleFileOptions;
use zip::{CompressionMethod, DateTime, ZipWriter};

use super::{
    Inner, NOT_IN_TRASH, Result, Store, StoreError, lock, open_stored_book_record,
    open_stored_entry,
};
use crate::{Id, ImageRef, ImageVariant};

/// The version of the Archive format this core writes. An Archive with a newer one cannot be
/// read by this core.
pub const ARCHIVE_FORMAT_VERSION: u64 = 1;

/// What `kronoer.json` says it is, so a reader can tell it from any other JSON file.
pub const ARCHIVE_FORMAT: &str = "kronoer-archive";

/// The Archive's data file: every Book and Entry.
pub const ARCHIVE_DATA_FILE: &str = "kronoer.json";

/// The Archive's note for whoever opens it without Kronoer.
pub const ARCHIVE_README_FILE: &str = "README.txt";

const README: &str = "\
Kronoer archive
===============

This file was exported from Kronoer. It is NOT encrypted: anyone who has it can
read every Entry in it. Keep it somewhere only you can open.

Inside:
- kronoer.json: every Book (name, Description, Cover) and every Entry (date,
  text, Images, when it was written and changed), which Entries are starred,
  and which Books are locked.
- images/: every Image and Cover, as JPEG, named by its ID.

Kronoer can bring it back: Settings > Import.

---

Arsip Kronoer
=============

File ini diekspor dari Kronoer. File ini TIDAK terenkripsi: siapa pun yang
memegangnya bisa membaca semua Entry di dalamnya. Simpan di tempat yang hanya
bisa kamu buka.

Isinya:
- kronoer.json: semua Book (nama, deskripsi, sampul) dan semua Entry (tanggal,
  teks, foto, kapan ditulis dan diubah), Entry mana yang berbintang, dan Book
  mana yang terkunci.
- images/: semua foto dan sampul, sebagai JPEG, dinamai menurut ID-nya.

Kronoer bisa memulihkannya: Pengaturan > Impor.
";

/// How far an Export has come, counted in Entries and Images written.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct ExportProgress {
    /// The Entries and Images written so far.
    pub done: u64,
    /// The Entries and Images the Archive holds, Covers included.
    pub total: u64,
}

/// What an Export wrote.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct ExportSummary {
    /// How many Books, Locked Books included.
    pub book_count: u32,
    /// How many Entries.
    pub entry_count: u32,
    /// How many Images, Covers included.
    pub image_count: u32,
}

/// A Book in `kronoer.json`.
#[derive(Serialize)]
struct ArchiveBook {
    id: String,
    name: String,
    description: String,
    cover_image_id: Option<String>,
}

/// An Entry in `kronoer.json`.
#[derive(Serialize)]
struct ArchiveEntry<'a> {
    id: String,
    book_id: String,
    entry_date: &'a str,
    text: &'a str,
    image_ids: Vec<String>,
    created_at: String,
    updated_at: String,
}

/// What the Archive will hold, read in one go before any byte is written.
struct Plan {
    books: Vec<ArchiveBook>,
    covers: Vec<ImageRef>,
    locked_book_ids: Vec<String>,
    starred_entry_ids: Vec<String>,
    entry_ids: Vec<Id>,
    entry_image_count: u64,
}

impl Store {
    /// Writes every Book not in the Trash, Locked Books included, with its Entries not in the
    /// Trash and their Images, into one unencrypted Archive. `exported_at` (milliseconds since
    /// the Unix epoch) is written as the Archive's time.
    ///
    /// `progress` is called after each Entry and each Image, and once before the first; returning
    /// `false` stops the Export with [`StoreError::Cancelled`]. Then, or on any other failure,
    /// what was written so far is not a whole Archive: the caller deletes it.
    ///
    /// Fails with [`StoreError::ArchiveWrite`] when writing to `out` fails, for example when its
    /// storage is full.
    pub fn export_archive<W: Write>(
        &self,
        out: W,
        exported_at: i64,
        mut progress: impl FnMut(ExportProgress) -> bool,
    ) -> Result<ExportSummary> {
        let plan = self.plan_export()?;
        let image_total = plan.entry_image_count + plan.covers.len() as u64;
        let total = plan.entry_ids.len() as u64 + image_total;
        let mut done = 0u64;
        let mut step = |done: u64| {
            if progress(ExportProgress { done, total }) {
                Ok(())
            } else {
                Err(StoreError::Cancelled)
            }
        };
        step(done)?;

        let mut out = BufWriter::new(out);
        let mut zip = ZipWriter::new_stream(&mut out);
        let time = zip_time(exported_at);
        let text = SimpleFileOptions::default()
            .compression_method(CompressionMethod::Deflated)
            .last_modified_time(time);
        // JPEG does not shrink: storing it as it is costs nothing.
        let image = SimpleFileOptions::default()
            .compression_method(CompressionMethod::Stored)
            .last_modified_time(time);

        zip.start_file(ARCHIVE_README_FILE, text)
            .map_err(zip_error)?;
        zip.write_all(README.as_bytes()).map_err(write_error)?;

        zip.start_file(ARCHIVE_DATA_FILE, text).map_err(zip_error)?;
        write_head(&mut zip, &plan, exported_at).map_err(write_error)?;
        let mut images = plan.covers;
        images.reserve(plan.entry_image_count as usize);
        for (i, &id) in plan.entry_ids.iter().enumerate() {
            let entry = {
                let mut inner = lock(&self.inner);
                let Inner { conn, keyring } = &mut *inner;
                open_stored_entry(conn, keyring, id)?
            };
            let archived = ArchiveEntry {
                id: entry.id.to_hex(),
                book_id: entry.book_id.to_hex(),
                entry_date: entry.date.as_str(),
                text: &entry.text,
                image_ids: entry
                    .images
                    .iter()
                    .map(|image| image.id().to_hex())
                    .collect(),
                created_at: utc_time(entry.created_at),
                updated_at: utc_time(entry.updated_at),
            };
            let separator: &[u8] = if i == 0 { b"\n    " } else { b",\n    " };
            zip.write_all(separator).map_err(write_error)?;
            serde_json::to_writer(&mut zip, &archived).map_err(json_error)?;
            images.extend(entry.images);
            done += 1;
            step(done)?;
        }
        let tail: &[u8] = if plan.entry_ids.is_empty() {
            b"]\n}\n"
        } else {
            b"\n  ]\n}\n"
        };
        zip.write_all(tail).map_err(write_error)?;

        let image_count = images.len() as u32;
        for image_ref in &images {
            let bytes = self.open_image_file(image_ref, ImageVariant::Full)?;
            zip.start_file(format!("images/{}.jpg", image_ref.id().to_hex()), image)
                .map_err(zip_error)?;
            zip.write_all(&bytes).map_err(write_error)?;
            done += 1;
            step(done)?;
        }

        zip.finish().map_err(zip_error)?;
        out.flush().map_err(write_error)?;
        Ok(ExportSummary {
            book_count: plan.books.len() as u32,
            entry_count: plan.entry_ids.len() as u32,
            image_count,
        })
    }

    /// How many Entries an Export would write: those not in the Trash, Locked Books included.
    pub fn exportable_entry_count(&self) -> Result<u32> {
        let inner = lock(&self.inner);
        Ok(inner.conn.query_row(
            &format!("SELECT count(*) FROM entry e WHERE {NOT_IN_TRASH}"),
            [],
            |row| row.get(0),
        )?)
    }

    /// Reads which Books, Entries, stars, and locks the Archive will hold, all at one moment.
    fn plan_export(&self) -> Result<Plan> {
        let mut inner = lock(&self.inner);
        let Inner { conn, keyring } = &mut *inner;
        let not_trashed_book = "NOT EXISTS (SELECT 1 FROM book_trash y WHERE y.book_id = b.id)";

        let book_ids = ids(
            conn,
            &format!(
                "SELECT b.id FROM book b WHERE {not_trashed_book}
                 ORDER BY b.last_activity_at DESC, b.id DESC"
            ),
        )?;
        let mut books = Vec::with_capacity(book_ids.len());
        let mut covers = Vec::new();
        for id in book_ids {
            let record = open_stored_book_record(conn, keyring, id)?;
            books.push(ArchiveBook {
                id: id.to_hex(),
                name: record.name,
                description: record.description,
                cover_image_id: record.cover.as_ref().map(|cover| cover.id().to_hex()),
            });
            covers.extend(record.cover);
        }

        let locked_book_ids = ids(
            conn,
            &format!(
                "SELECT b.id FROM book b JOIN book_lock k ON k.book_id = b.id
                 WHERE {not_trashed_book}
                 ORDER BY b.last_activity_at DESC, b.id DESC"
            ),
        )?;
        let starred_entry_ids = ids(
            conn,
            &format!(
                "SELECT e.id FROM entry e JOIN star s ON s.entry_id = e.id WHERE {NOT_IN_TRASH}
                 ORDER BY e.entry_date, e.created_at, e.id"
            ),
        )?;
        let entry_ids = ids(
            conn,
            &format!(
                "SELECT e.id FROM entry e WHERE {NOT_IN_TRASH}
                 ORDER BY e.entry_date, e.created_at, e.id"
            ),
        )?;
        let entry_image_count: u32 = conn.query_row(
            &format!(
                "SELECT count(*) FROM entry_image i JOIN entry e ON e.id = i.entry_id
                 WHERE {NOT_IN_TRASH}"
            ),
            [],
            |row| row.get(0),
        )?;
        Ok(Plan {
            books,
            covers,
            locked_book_ids: locked_book_ids.iter().map(Id::to_hex).collect(),
            starred_entry_ids: starred_entry_ids.iter().map(Id::to_hex).collect(),
            entry_ids,
            entry_image_count: u64::from(entry_image_count),
        })
    }
}

fn ids(conn: &rusqlite::Connection, sql: &str) -> Result<Vec<Id>> {
    let mut statement = conn.prepare(sql)?;
    let ids = statement
        .query_map([], |row| row.get(0))?
        .collect::<rusqlite::Result<_>>()?;
    Ok(ids)
}

/// Writes `kronoer.json` up to the opening of its Entry list, one key per line.
fn write_head(out: &mut impl Write, plan: &Plan, exported_at: i64) -> io::Result<()> {
    fn field(out: &mut impl Write, key: &str, value: &impl Serialize) -> io::Result<()> {
        write!(out, "  \"{key}\": ")?;
        serde_json::to_writer(&mut *out, value)?;
        out.write_all(b",\n")
    }
    out.write_all(b"{\n")?;
    field(out, "format", &ARCHIVE_FORMAT)?;
    field(out, "format_version", &ARCHIVE_FORMAT_VERSION)?;
    field(out, "exported_at", &utc_time(exported_at))?;
    out.write_all(b"  \"books\": [")?;
    for (i, book) in plan.books.iter().enumerate() {
        out.write_all(if i == 0 { b"\n    " } else { b",\n    " })?;
        serde_json::to_writer(&mut *out, book)?;
    }
    out.write_all(if plan.books.is_empty() {
        b"],\n"
    } else {
        b"\n  ],\n"
    })?;
    field(out, "locked_book_ids", &plan.locked_book_ids)?;
    field(out, "starred_entry_ids", &plan.starred_entry_ids)?;
    out.write_all(b"  \"entries\": [")
}

/// A time in milliseconds since the Unix epoch, in UTC as RFC 3339 with milliseconds:
/// `2026-11-24T04:30:00.000Z`.
pub(crate) fn utc_time(ms: i64) -> String {
    let (days, ms_of_day) = (ms.div_euclid(86_400_000), ms.rem_euclid(86_400_000));
    let (year, month, day) = civil_from_days(days);
    let seconds = ms_of_day / 1000;
    format!(
        "{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}.{:03}Z",
        seconds / 3600,
        seconds / 60 % 60,
        seconds % 60,
        ms_of_day % 1000
    )
}

/// The proleptic Gregorian date of a day counted from 1970-01-01 (Howard Hinnant's algorithm).
fn civil_from_days(days: i64) -> (i64, u32, u32) {
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let month = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    let year = yoe + era * 400 + i64::from(month <= 2);
    (year, month, day)
}

/// The Archive's time for every file in the ZIP, which keeps only local-less times from 1980 to
/// 2107, in two-second steps.
fn zip_time(ms: i64) -> DateTime {
    let (days, ms_of_day) = (ms.div_euclid(86_400_000), ms.rem_euclid(86_400_000));
    let (year, month, day) = civil_from_days(days);
    let seconds = ms_of_day / 1000;
    u16::try_from(year)
        .ok()
        .and_then(|year| {
            DateTime::from_date_and_time(
                year,
                month as u8,
                day as u8,
                (seconds / 3600) as u8,
                (seconds / 60 % 60) as u8,
                (seconds % 60) as u8,
            )
            .ok()
        })
        .unwrap_or_default()
}

fn write_error(error: io::Error) -> StoreError {
    StoreError::ArchiveWrite(error)
}

fn json_error(error: serde_json::Error) -> StoreError {
    StoreError::ArchiveWrite(error.into())
}

fn zip_error(error: zip::result::ZipError) -> StoreError {
    match error {
        zip::result::ZipError::Io(error) => StoreError::ArchiveWrite(error),
        error => StoreError::ArchiveWrite(io::Error::other(error)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn utc_times() {
        assert_eq!(utc_time(0), "1970-01-01T00:00:00.000Z");
        assert_eq!(utc_time(1_795_494_824_123), "2026-11-24T04:33:44.123Z");
        assert_eq!(utc_time(951_782_400_000), "2000-02-29T00:00:00.000Z");
        assert_eq!(utc_time(-1), "1969-12-31T23:59:59.999Z");
    }
}
