//! Book insight: what a Book holds, as counts. Everything is counted on the device from the
//! index, without opening a blob.

/// How many Entries, words, and Images a Book holds.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub struct BookInsight {
    /// Every Entry in the Book.
    pub entry_count: u32,
    /// The words in the text of all the Book's Entries, by [`count_words`].
    pub word_count: u32,
    /// Every Image of the Book's Entries. The Cover is not one.
    pub image_count: u32,
}

/// How many words `text`, an Entry's text as written, holds.
///
/// A word is a piece of text between white space that holds a letter or a digit, so Text style
/// marks standing alone (`*`, `-`, `>`, ```` ``` ````) are not words, and marks around a word
/// (`*bold*`) do not make it another. The number of a numbered list item (`12. `) is a mark too,
/// not a word.
pub fn count_words(text: &str) -> u32 {
    text.lines()
        .map(|line| {
            let line = line.strip_prefix("> ").unwrap_or(line);
            let line = without_list_number(line);
            line.split_whitespace()
                .filter(|piece| piece.chars().any(char::is_alphanumeric))
                .count() as u32
        })
        .sum()
}

/// `line` without the number of a numbered list item it starts with, as in `12. `.
fn without_list_number(line: &str) -> &str {
    let digits = line.len() - line.trim_start_matches(|c: char| c.is_ascii_digit()).len();
    match line[digits..].strip_prefix(". ") {
        Some(rest) if digits > 0 => rest,
        _ => line,
    }
}

#[cfg(test)]
mod tests {
    use super::count_words;

    #[test]
    fn counts_pieces_between_white_space() {
        assert_eq!(count_words(""), 0);
        assert_eq!(count_words("   \n\n "), 0);
        assert_eq!(count_words("Pagi ini hujan."), 3);
        assert_eq!(count_words("Pagi\tini\n\nhujan,  lagi"), 4);
        assert_eq!(count_words("9.12 lebih kecil dari 9.8"), 5);
        assert_eq!(count_words("jam 07:30, kopi-susu"), 3);
    }

    #[test]
    fn text_style_marks_are_not_words() {
        assert_eq!(count_words("*tebal* _miring_ ~coret~ `kode`"), 4);
        assert_eq!(count_words("*_tebal miring_*"), 2);
        assert_eq!(count_words("- satu\n* dua\n> kutipan ini"), 4);
        assert_eq!(count_words("1. satu\n12. dua belas"), 3);
        assert_eq!(count_words("> 3. kutipan"), 1);
        assert_eq!(count_words("```\nlet x = 1;\n```"), 3);
        assert_eq!(count_words("# judul - bukan -> kata"), 3);
    }

    #[test]
    fn numbers_in_the_text_are_words() {
        assert_eq!(count_words("2 * 3 * 4"), 3);
        assert_eq!(count_words("Ada 3 kucing. 12.30 pulang"), 5);
        assert_eq!(count_words("12.tanpa spasi"), 2);
    }

    #[test]
    fn pieces_without_letters_or_digits_are_not_words() {
        assert_eq!(count_words("wkwk 😂 !!"), 1);
        assert_eq!(count_words("café naïve 東京"), 3);
    }
}
