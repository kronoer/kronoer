//! Turning what a person types into an FTS5 query, and finding where it matches.

use std::ops::Range;

use rusqlite::{Connection, OptionalExtension};

use super::StoreError;

/// Marks the start of a match in a snippet. A private-use character, so it never clashes with text.
pub const MATCH_START: char = '\u{e000}';
/// Marks the end of a match in a snippet.
pub const MATCH_END: char = '\u{e001}';

/// The tokenizer of the search index. [`match_ranges`] uses the same one, so it finds exactly the
/// words a search matched.
pub(crate) const TOKENIZER: &str = "unicode61 remove_diacritics 2";

/// Stands in for a marker found in the text itself. Also private use, so the tokenizer still reads
/// it as part of a word, and also three bytes in UTF-8, so no offset moves.
const MARKER_STAND_IN: char = '\u{e002}';

/// An FTS5 query in which every word typed must match the start of a word in the Entry.
///
/// Words are split the way the `unicode61` tokenizer splits them, on anything that is not a letter
/// or digit, so nothing typed can be read as FTS5 syntax. `None` when nothing searchable was typed.
pub(crate) fn match_query(typed: &str) -> Option<String> {
    let terms: Vec<String> = typed
        .split(|c: char| !c.is_alphanumeric())
        .filter(|word| !word.is_empty())
        .map(|word| format!("\"{word}\"*"))
        .collect();
    (!terms.is_empty()).then(|| terms.join(" "))
}

/// Where a search for `typed` matches `text`, as byte ranges in order: each one a whole word of
/// `text` that starts with a word typed, by the same rules as [`super::Store::search`].
///
/// Empty when not every word typed matches, as the search would not have found `text` either.
/// The text goes into an in-memory database only, which is dropped before this returns.
pub fn match_ranges(text: &str, typed: &str) -> Result<Vec<Range<usize>>, StoreError> {
    let Some(query) = match_query(typed) else {
        return Ok(Vec::new());
    };
    let text: String = text
        .chars()
        .map(|c| match c {
            MATCH_START | MATCH_END => MARKER_STAND_IN,
            c => c,
        })
        .collect();

    let conn = Connection::open_in_memory()?;
    conn.execute_batch(&format!(
        "CREATE VIRTUAL TABLE t USING fts5 (text, tokenize = '{TOKENIZER}')"
    ))?;
    conn.execute("INSERT INTO t (text) VALUES (?1)", [&text])?;
    let Some(highlighted) = conn
        .query_row(
            &format!(
                "SELECT highlight(t, 0, '{MATCH_START}', '{MATCH_END}') FROM t WHERE t MATCH ?1"
            ),
            [&query],
            |row| row.get::<_, String>(0),
        )
        .optional()?
    else {
        return Ok(Vec::new());
    };

    let mut ranges = Vec::new();
    let mut offset = 0;
    let mut start = None;
    for c in highlighted.chars() {
        match c {
            MATCH_START => start = Some(offset),
            MATCH_END => ranges.extend(start.take().map(|start| start..offset)),
            c => offset += c.len_utf8(),
        }
    }
    Ok(ranges)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_word_becomes_a_quoted_prefix() {
        assert_eq!(
            match_query("pagi hujan").as_deref(),
            Some("\"pagi\"* \"hujan\"*")
        );
    }

    #[test]
    fn syntax_and_punctuation_are_only_separators() {
        assert_eq!(
            match_query("\"kopi\" OR -teh* (NEAR)").as_deref(),
            Some("\"kopi\"* \"OR\"* \"teh\"* \"NEAR\"*")
        );
        assert_eq!(match_query("  ...  ").as_deref(), None);
        assert_eq!(match_query("").as_deref(), None);
    }

    #[test]
    fn keeps_letters_with_diacritics() {
        assert_eq!(match_query("café").as_deref(), Some("\"café\"*"));
    }

    /// The parts of `text` that `typed` matches.
    fn matches<'t>(text: &'t str, typed: &str) -> Vec<&'t str> {
        match_ranges(text, typed)
            .unwrap()
            .into_iter()
            .map(|range| &text[range])
            .collect()
    }

    #[test]
    fn matches_whole_words_by_their_start() {
        assert_eq!(
            matches("Hujan lagi. Kehujanan, tapi hujannya reda.", "huj"),
            ["Hujan", "hujannya"]
        );
    }

    #[test]
    fn matches_with_or_without_diacritics() {
        assert_eq!(matches("Ngopi di café dekat rumah", "cafe"), ["café"]);
        assert_eq!(matches("Ngopi di cafe dekat rumah", "café"), ["cafe"]);
    }

    #[test]
    fn matches_every_word_typed() {
        assert_eq!(
            matches("Pagi ini hujan, pagi kemarin cerah.", "hujan pagi"),
            ["Pagi", "hujan", "pagi"]
        );
    }

    #[test]
    fn nothing_when_a_word_typed_is_missing() {
        assert!(matches("Pagi ini hujan.", "hujan senja").is_empty());
        assert!(matches("Pagi ini hujan.", "senja").is_empty());
        assert!(matches("Pagi ini hujan.", " ... ").is_empty());
        assert!(matches("", "hujan").is_empty());
    }

    #[test]
    fn ranges_are_byte_offsets_into_the_text() {
        let text = "Ké 🌧 hujan";
        assert_eq!(match_ranges(text, "hujan").unwrap(), vec![9..14]);
    }

    #[test]
    fn markers_in_the_text_are_not_read_as_matches() {
        let text = format!("a{MATCH_START}b hujan {MATCH_END}");
        assert_eq!(matches(&text, "hujan"), ["hujan"]);
    }

    #[test]
    fn the_index_uses_the_same_tokenizer() {
        assert!(super::super::schema::MIGRATIONS[0].contains(&format!("tokenize = '{TOKENIZER}'")));
    }
}
