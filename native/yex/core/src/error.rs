use std::fmt;

use yrs::encoding::read::Error as ReadError;
use yrs::error::UpdateError;

/// Why bytes from outside could not be decoded or applied.
#[derive(Debug)]
pub enum WireError {
    /// The bytes are malformed, or yrs panicked on them.
    Encoding(ReadError),
    /// The update decoded but yrs refused to integrate it.
    Update(UpdateError),
}

impl fmt::Display for WireError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            WireError::Encoding(e) => e.fmt(f),
            WireError::Update(e) => e.fmt(f),
        }
    }
}

impl std::error::Error for WireError {}

impl From<ReadError> for WireError {
    fn from(e: ReadError) -> Self {
        WireError::Encoding(e)
    }
}

impl From<UpdateError> for WireError {
    fn from(e: UpdateError) -> Self {
        WireError::Update(e)
    }
}
