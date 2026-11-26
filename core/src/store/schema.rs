//! The database schema and its migrations. The schema version lives in `PRAGMA user_version`.
//!
//! Every plaintext column and the search index can be rebuilt from the blobs, except `book_pin`,
//! `book_out_of_timeline`, and the Trash tables and setting, which are this device's own.
//! Stars and Book locks are kept as their sealed records, like Entries as their blobs.

use rusqlite::{Connection, Transaction};

use super::{Keyring, StoreError};

/// A migration step that needs the Book keys.
type KeyedStep = fn(&Transaction<'_>, &mut Keyring) -> Result<(), StoreError>;

/// One schema version's change: SQL, then optionally a step that needs the Book keys, both in one
/// transaction.
pub(super) struct Migration {
    pub(super) sql: &'static str,
    pub(super) with_keys: Option<KeyedStep>,
}

/// One migration per schema version, in order. Migration `i` takes the database from version `i`
/// to version `i + 1`; its SQL is the file in `migrations/` numbered `i + 1`. Never change a
/// migration once it has shipped; add a new one.
pub(super) const MIGRATIONS: &[Migration] = &[Migration {
    sql: include_str!("migrations/00001_init.sql"),
    with_keys: None,
}];

/// The schema version this crate writes.
pub(crate) const VERSION: u32 = MIGRATIONS.len() as u32;

/// Brings the database to [`VERSION`], one migration per transaction.
///
/// Fails with [`StoreError::NewerSchema`] if a newer version of the app already changed it.
pub(crate) fn migrate(conn: &mut Connection, keyring: &mut Keyring) -> Result<(), StoreError> {
    let current: u32 = conn.query_row("PRAGMA user_version", [], |row| row.get(0))?;
    if current > VERSION {
        return Err(StoreError::NewerSchema(current));
    }
    for (index, migration) in MIGRATIONS.iter().enumerate().skip(current as usize) {
        let tx = conn.transaction()?;
        tx.execute_batch(migration.sql)?;
        if let Some(with_keys) = migration.with_keys {
            with_keys(&tx, keyring)?;
        }
        tx.pragma_update(None, "user_version", index as u32 + 1)?;
        tx.commit()?;
    }
    Ok(())
}
