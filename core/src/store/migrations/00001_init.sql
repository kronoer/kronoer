-- Schema version 1. Never change it once it has shipped; add a new migration.

CREATE TABLE book (
    id BLOB PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    -- The Image ID of the Book's Cover, if it has one.
    cover_id BLOB,
    last_activity_at INTEGER NOT NULL,
    record BLOB NOT NULL,
    record_key_version INTEGER NOT NULL
) WITHOUT ROWID;
CREATE UNIQUE INDEX book_by_cover ON book (cover_id);

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
-- Entries with the same Entry date come in the order they were written. Each index serves both
-- orders.
CREATE INDEX entry_by_book_and_date ON entry (book_id, entry_date, created_at, id);
CREATE INDEX entry_by_date ON entry (entry_date, created_at, id);
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

-- Pinned Books. A pin belongs to this device only: it is not in the Book record, so it is
-- never sealed, exported, or sent.
CREATE TABLE book_pin (
    book_id BLOB PRIMARY KEY REFERENCES book (id) ON DELETE CASCADE
) WITHOUT ROWID;

-- Books the user keeps out of the Timeline. Like a pin, this is this device's own choice,
-- never sealed, exported, or sent. A Book is in the Timeline unless it is listed here.
CREATE TABLE book_out_of_timeline (
    book_id BLOB PRIMARY KEY REFERENCES book (id) ON DELETE CASCADE
) WITHOUT ROWID;

-- Starred Entries, one sealed Star record each. Unlike a pin, a star is sealed and travels
-- with the user; the other columns can be rebuilt from the record.
CREATE TABLE star (
    record_id BLOB PRIMARY KEY,
    entry_id BLOB NOT NULL UNIQUE REFERENCES entry (id) ON DELETE CASCADE,
    book_id BLOB NOT NULL,
    starred_at INTEGER NOT NULL,
    record BLOB NOT NULL
) WITHOUT ROWID;
CREATE INDEX star_by_book ON star (book_id);

-- The Trash, as when each Book or Entry in it was deleted. Like a pin, it is this device's
-- own, never sealed, exported, or sent. An Entry of a Book in the Trash has a row only if it
-- was deleted before the Book; the others went with the Book and come back with it.
CREATE TABLE book_trash (
    book_id BLOB PRIMARY KEY REFERENCES book (id) ON DELETE CASCADE,
    deleted_at INTEGER NOT NULL
) WITHOUT ROWID;
CREATE TABLE entry_trash (
    entry_id BLOB PRIMARY KEY REFERENCES entry (id) ON DELETE CASCADE,
    deleted_at INTEGER NOT NULL
) WITHOUT ROWID;

-- How many days the Trash keeps what is deleted, this device's own choice. No row means the
-- default.
CREATE TABLE trash_setting (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    days INTEGER NOT NULL
);

-- Locked Books, one sealed Lock record each. Like a star, a lock is sealed and travels with
-- the user; the other columns can be rebuilt from the record. It stays while the Book is in
-- the Trash and goes with the Book when it is deleted for good.
CREATE TABLE book_lock (
    record_id BLOB PRIMARY KEY,
    book_id BLOB NOT NULL UNIQUE REFERENCES book (id) ON DELETE CASCADE,
    locked_at INTEGER NOT NULL,
    record BLOB NOT NULL
) WITHOUT ROWID;
