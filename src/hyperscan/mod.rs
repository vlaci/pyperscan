// SPDX-FileCopyrightText: 2022 László Vaskó <opensource@vlaci.email>
//
// SPDX-License-Identifier: MIT OR Apache-2.0

mod error;
mod native;
mod wrapper;

pub(crate) use error::{AsResult, Error, HyperscanErrorCode};
pub(crate) use native::*;
pub(crate) use wrapper::{Flag, Pattern, ScanMode};
