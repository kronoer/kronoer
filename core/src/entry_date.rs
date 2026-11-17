use std::fmt;

use crate::Error;

/// The date and time an Entry is about: the local time where the author was, with that place's
/// UTC offset, as `YYYY-MM-DDTHH:MM:SS±HH:MM`.
///
/// It keeps the local time as written, so an Entry stays on its day wherever it is read.
#[derive(Clone, PartialEq, Eq, Hash)]
pub struct EntryDate(String);

/// The largest UTC offset allowed, in minutes.
const MAX_OFFSET_MINUTES: u32 = 18 * 60;

impl EntryDate {
    /// Reads an Entry date, rejecting anything outside the form in `spec/entry-format.md`.
    pub fn parse(text: &str) -> Result<EntryDate, Error> {
        if is_valid(text.as_bytes()) {
            Ok(EntryDate(text.to_owned()))
        } else {
            Err(Error::InvalidEntryDate)
        }
    }

    /// The Entry date as text.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Debug for EntryDate {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "EntryDate({})", self.0)
    }
}

impl fmt::Display for EntryDate {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

// YYYY-MM-DDTHH:MM:SS+HH:MM
// 0123456789012345678901234
fn is_valid(text: &[u8]) -> bool {
    if text.len() != 25 {
        return false;
    }
    let separators = [
        (4, b'-'),
        (7, b'-'),
        (10, b'T'),
        (13, b':'),
        (16, b':'),
        (22, b':'),
    ];
    if separators.iter().any(|&(at, c)| text[at] != c) {
        return false;
    }
    let sign = text[19];
    if sign != b'+' && sign != b'-' {
        return false;
    }
    let number = |from: usize, to: usize| -> Option<u32> {
        text[from..to].iter().try_fold(0u32, |n, &d| {
            d.is_ascii_digit().then(|| n * 10 + u32::from(d - b'0'))
        })
    };
    let (Some(year), Some(month), Some(day)) = (number(0, 4), number(5, 7), number(8, 10)) else {
        return false;
    };
    let (Some(hour), Some(minute), Some(second)) = (number(11, 13), number(14, 16), number(17, 19))
    else {
        return false;
    };
    let (Some(offset_hours), Some(offset_minutes)) = (number(20, 22), number(23, 25)) else {
        return false;
    };
    let offset = offset_hours * 60 + offset_minutes;

    year >= 1
        && (1..=12).contains(&month)
        && day >= 1
        && day <= days_in_month(year, month)
        && hour < 24
        && minute < 60
        && second < 60
        && offset_minutes < 60
        && offset <= MAX_OFFSET_MINUTES
        && !(sign == b'-' && offset == 0)
}

fn days_in_month(year: u32, month: u32) -> u32 {
    match month {
        2 if year.is_multiple_of(4) && (!year.is_multiple_of(100) || year.is_multiple_of(400)) => {
            29
        }
        2 => 28,
        4 | 6 | 9 | 11 => 30,
        _ => 31,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_valid_dates() {
        for text in [
            "2026-11-17T23:30:00+07:00",
            "2026-11-17T00:00:00+00:00",
            "2024-02-29T12:00:00-03:30",
            "2000-02-29T12:00:00+05:45",
            "0001-01-01T00:00:00+18:00",
            "9999-12-31T23:59:59-18:00",
        ] {
            assert_eq!(EntryDate::parse(text).unwrap().as_str(), text);
        }
    }

    #[test]
    fn rejects_invalid_dates() {
        for text in [
            "",
            "2026-11-17T23:30:00Z",
            "2026-11-17T23:30:00.000+07:00",
            "2026-11-17 23:30:00+07:00",
            "2026-11-17t23:30:00+07:00",
            "2026-11-17T23:30+07:00",
            "0000-01-01T00:00:00+00:00",
            "2026-00-10T00:00:00+00:00",
            "2026-13-10T00:00:00+00:00",
            "2026-02-29T00:00:00+00:00",
            "1900-02-29T00:00:00+00:00",
            "2026-04-31T00:00:00+00:00",
            "2026-11-17T24:00:00+00:00",
            "2026-11-17T23:60:00+00:00",
            "2026-11-17T23:59:60+00:00",
            "2026-11-17T23:30:00-00:00",
            "2026-11-17T23:30:00+18:01",
            "2026-11-17T23:30:00+07:60",
            "2026-11-17T23:30:00 07:00",
            "2026-1a-17T23:30:00+07:00",
            "+026-11-17T23:30:00+07:00",
        ] {
            assert_eq!(
                EntryDate::parse(text),
                Err(Error::InvalidEntryDate),
                "{text}"
            );
        }
    }
}
