//! Deterministic CBOR: helpers that write it and read it strictly.
//!
//! Readers decode a structure, encode it again, and compare the bytes, so anything that is not in
//! deterministic form is rejected.

use std::convert::Infallible;

use minicbor::{Decoder, Encoder};

use crate::Error;

pub(crate) type Writer = Encoder<Vec<u8>>;
pub(crate) type WriteResult = Result<(), minicbor::encode::Error<Infallible>>;

/// Encodes with `write`. Writing to a `Vec` cannot fail.
pub(crate) fn encode(write: impl FnOnce(&mut Writer) -> WriteResult) -> Vec<u8> {
    let mut writer = Encoder::new(Vec::new());
    write(&mut writer).expect("writing to a Vec cannot fail");
    writer.into_writer()
}

/// Checks that `input` is exactly the deterministic encoding of what was decoded from it.
pub(crate) fn check_canonical(input: &[u8], encoded_again: &[u8]) -> Result<(), Error> {
    if input == encoded_again {
        Ok(())
    } else {
        Err(Error::NonCanonical)
    }
}

/// Checks that the decoder read the whole input.
pub(crate) fn finish(decoder: &Decoder<'_>, input: &[u8]) -> Result<(), Error> {
    if decoder.position() == input.len() {
        Ok(())
    } else {
        Err(Error::Malformed)
    }
}

/// Reads the start of an array and returns its length. Indefinite lengths are not deterministic.
pub(crate) fn array(decoder: &mut Decoder<'_>) -> Result<u64, Error> {
    match decoder.array().map_err(|_| Error::Malformed)? {
        Some(len) => Ok(len),
        None => Err(Error::NonCanonical),
    }
}

/// Reads the start of an array that must have `len` items.
pub(crate) fn array_of(decoder: &mut Decoder<'_>, len: u64) -> Result<(), Error> {
    if array(decoder)? == len {
        Ok(())
    } else {
        Err(Error::Malformed)
    }
}

pub(crate) fn uint(decoder: &mut Decoder<'_>) -> Result<u64, Error> {
    decoder.u64().map_err(|_| Error::Malformed)
}

pub(crate) fn int(decoder: &mut Decoder<'_>) -> Result<i64, Error> {
    decoder.i64().map_err(|_| Error::Malformed)
}

pub(crate) fn text<'b>(decoder: &mut Decoder<'b>) -> Result<&'b str, Error> {
    decoder.str().map_err(|_| Error::Malformed)
}

pub(crate) fn bytes<'b>(decoder: &mut Decoder<'b>) -> Result<&'b [u8], Error> {
    decoder.bytes().map_err(|_| Error::Malformed)
}

/// Reads a byte string that must be exactly `N` bytes long.
pub(crate) fn bytes_of<const N: usize>(decoder: &mut Decoder<'_>) -> Result<[u8; N], Error> {
    bytes(decoder)?.try_into().map_err(|_| Error::Malformed)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn writes_the_shortest_integer_form() {
        let bytes = encode(|w| {
            w.array(3)?.u64(23)?.u64(24)?.i64(-1)?;
            Ok(())
        });

        assert_eq!(bytes, [0x83, 0x17, 0x18, 0x18, 0x20]);
    }

    #[test]
    fn rejects_indefinite_arrays() {
        let input = [0x9f, 0x01, 0xff];

        assert_eq!(array(&mut Decoder::new(&input)), Err(Error::NonCanonical));
    }

    #[test]
    fn rejects_trailing_bytes() {
        let input = [0x01, 0x02];
        let mut decoder = Decoder::new(&input);
        uint(&mut decoder).unwrap();

        assert_eq!(finish(&decoder, &input), Err(Error::Malformed));
    }

    #[test]
    fn rejects_wrong_lengths_and_types() {
        assert_eq!(
            bytes_of::<2>(&mut Decoder::new(&[0x43, 1, 2, 3])),
            Err(Error::Malformed)
        );
        assert_eq!(uint(&mut Decoder::new(&[0x20])), Err(Error::Malformed));
        assert_eq!(
            text(&mut Decoder::new(&[0x41, 0x61])),
            Err(Error::Malformed)
        );
    }
}
