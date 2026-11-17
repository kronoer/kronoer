//! Lowercase hexadecimal, the text form of IDs and of bytes in test vectors.

const DIGITS: &[u8; 16] = b"0123456789abcdef";

pub(crate) fn encode(bytes: &[u8]) -> String {
    let mut text = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        text.push(DIGITS[usize::from(byte >> 4)] as char);
        text.push(DIGITS[usize::from(byte & 0x0f)] as char);
    }
    text
}

/// Decodes lowercase hexadecimal. Uppercase digits and odd lengths are rejected.
pub(crate) fn decode(text: &str) -> Option<Vec<u8>> {
    fn value(digit: u8) -> Option<u8> {
        match digit {
            b'0'..=b'9' => Some(digit - b'0'),
            b'a'..=b'f' => Some(digit - b'a' + 10),
            _ => None,
        }
    }

    let (pairs, rest) = text.as_bytes().as_chunks::<2>();
    if !rest.is_empty() {
        return None;
    }
    pairs
        .iter()
        .map(|&[high, low]| Some(value(high)? << 4 | value(low)?))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips() {
        let bytes = [0x00, 0x7f, 0x80, 0xff, 0x0a];

        assert_eq!(encode(&bytes), "007f80ff0a");
        assert_eq!(decode("007f80ff0a").unwrap(), bytes);
    }

    #[test]
    fn rejects_uppercase_odd_length_and_other_characters() {
        assert_eq!(decode("0A"), None);
        assert_eq!(decode("abc"), None);
        assert_eq!(decode("0g"), None);
    }
}
