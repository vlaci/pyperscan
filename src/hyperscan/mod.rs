mod error;
mod native;
mod wrapper;

pub(crate) use error::{AsResult, Error, HyperscanErrorCode};
pub(crate) use native::*;
pub(crate) use wrapper::{Flag, Pattern, ScanMode};
