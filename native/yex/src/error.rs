use crate::atoms;
use rustler::{Atom, NifTuple};

#[derive(NifTuple)]
pub struct NifError {
    pub reason: Atom,
    pub message: String,
}

impl From<yrs::doc::TransactionAcqError> for NifError {
    fn from(w: yrs::doc::TransactionAcqError) -> NifError {
        NifError {
            reason: atoms::transaction_acq_error(),
            message: w.to_string(),
        }
    }
}

impl From<yrs::encoding::read::Error> for NifError {
    fn from(w: yrs::encoding::read::Error) -> NifError {
        NifError {
            reason: atoms::error(),
            message: w.to_string(),
        }
    }
}

impl From<rustler::Error> for NifError {
    fn from(_w: rustler::Error) -> NifError {
        NifError {
            reason: atoms::error(),
            message: "todo".to_string(),
        }
    }
}
