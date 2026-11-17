//! Random bytes from the operating system.

use zeroize::Zeroizing;

use crate::Error;

pub(crate) fn bytes<const N: usize>() -> Result<[u8; N], Error> {
    let mut bytes = [0u8; N];
    getrandom::fill(&mut bytes).map_err(|_| Error::RandomUnavailable)?;
    Ok(bytes)
}

/// Random bytes for a secret, wiped from memory when dropped.
pub(crate) fn secret<const N: usize>() -> Result<Zeroizing<[u8; N]>, Error> {
    let mut bytes = Zeroizing::new([0u8; N]);
    getrandom::fill(bytes.as_mut()).map_err(|_| Error::RandomUnavailable)?;
    Ok(bytes)
}
