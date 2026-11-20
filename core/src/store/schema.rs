//! The database schema and its migrations. The schema version lives in `PRAGMA user_version`.
//!
//! Every plaintext column and the search index can be rebuilt from the blobs: they only exist so
//! lists, ordering, and search do not have to open every blob.

use rusqlite::Connection;

use super::StoreError;

/// One migration per schema version, in order. Migration `i` takes the database from version `i`
/// to version `i + 1`. Never change a migration once it has shipped; add a new one.
pub(super) const MIGRATIONS: &[&str] = &[
    // Version 1.
    "
    CREATE TABLE book (
        id BLOB PRIMARY KEY,
        name TEXT NOT NULL,
        last_activity_at INTEGER NOT NULL,
        record BLOB NOT NULL,
        record_key_version INTEGER NOT NULL
    ) WITHOUT ROWID;

    CREATE TABLE book_key (
        book_id BLOB NOT NULL REFERENCES book (id) ON DELETE CASCADE,
        version INTEGER NOT NULL,
        wrapped BLOB NOT NULL,
        PRIMARY KEY (book_id, version)
    ) WITHOUT ROWID;

    CREATE TABLE entry (
        seq INTEGER PRIMARY KEY,
        id BLOB NOT NULL UNIQUE,
        book_id BLOB NOT NULL REFERENCES book (id) ON DELETE CASCADE,
        book_key_version INTEGER NOT NULL,
        entry_date TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        blob BLOB NOT NULL
    );
    CREATE INDEX entry_by_book_and_date ON entry (book_id, entry_date DESC, id DESC);
    CREATE INDEX entry_by_date ON entry (entry_date DESC, id DESC);
    CREATE INDEX entry_by_book_and_update ON entry (book_id, updated_at DESC, id DESC);

    CREATE TABLE entry_image (
        entry_id BLOB NOT NULL REFERENCES entry (id) ON DELETE CASCADE,
        position INTEGER NOT NULL,
        image_id BLOB NOT NULL UNIQUE,
        PRIMARY KEY (entry_id, position)
    ) WITHOUT ROWID;

    -- The text of each Entry, by entry.seq. It keeps the text, for snippets and list previews.
    CREATE VIRTUAL TABLE entry_search USING fts5 (
        text,
        tokenize = 'unicode61 remove_diacritics 2',
        prefix = '2 3'
    );
    ",
];

/// The schema version this crate writes.
pub(crate) const VERSION: u32 = MIGRATIONS.len() as u32;

/// Brings the database to [`VERSION`], one migration per transaction.
///
/// Fails with [`StoreError::NewerSchema`] if a newer version of the app already changed it.
pub(crate) fn migrate(conn: &mut Connection) -> Result<(), StoreError> {
    let current: u32 = conn.query_row("PRAGMA user_version", [], |row| row.get(0))?;
    if current > VERSION {
        return Err(StoreError::NewerSchema(current));
    }
    for (index, migration) in MIGRATIONS.iter().enumerate().skip(current as usize) {
        let tx = conn.transaction()?;
        tx.execute_batch(migration)?;
        tx.pragma_update(None, "user_version", index as u32 + 1)?;
        tx.commit()?;
    }
    Ok(())
}
