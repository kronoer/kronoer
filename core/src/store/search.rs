//! Turning what a person types into an FTS5 query.

/// Marks the start of a match in a snippet. A private-use character, so it never clashes with text.
pub const MATCH_START: char = '\u{e000}';
/// Marks the end of a match in a snippet.
pub const MATCH_END: char = '\u{e001}';

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
}
