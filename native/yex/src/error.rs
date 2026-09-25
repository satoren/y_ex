use rustler::NifException;

use crate::atoms;

#[derive(Debug, NifException)]
#[module = "Yex.TransactionAcqError"]
pub struct TransactionAcqError {
    message: String,
}

impl TransactionAcqError {
    fn new() -> Self {
        TransactionAcqError {
            message: "Failed to acquire transaction: another transaction is in progress"
                .to_string(),
        }
    }
}

#[derive(Debug)]
pub enum Error {
    Transaction,
    Update(yrs::error::UpdateError),
    Encoding(yrs::encoding::read::Error),
    Awareness(yrs::sync::awareness::Error),
    Rustler(rustler::Error),
    Message(String),
}

impl rustler::Encoder for Error {
    fn encode<'a>(&self, env: rustler::Env<'a>) -> rustler::Term<'a> {
        match self {
            Error::Transaction => TransactionAcqError::new().encode(env),
            Error::Encoding(error) => (
                atoms::error(),
                (atoms::encoding_exception(), error.to_string()),
            )
                .encode(env),
            Error::Update(error) => (atoms::error(), error.to_string()).encode(env),
            Error::Awareness(error) => (atoms::error(), error.to_string()).encode(env),
            Error::Message(error) => (atoms::error(), error).encode(env),
            Error::Rustler(_) => panic!("RustlerError not supported"),
        }
    }
}

impl From<yrs::error::UpdateError> for Error {
    fn from(error: yrs::error::UpdateError) -> Self {
        Error::Update(error)
    }
}
impl From<yrs::encoding::read::Error> for Error {
    fn from(error: yrs::encoding::read::Error) -> Self {
        Error::Encoding(error)
    }
}
impl From<yrs::sync::awareness::Error> for Error {
    fn from(error: yrs::sync::awareness::Error) -> Self {
        Error::Awareness(error)
    }
}
impl From<rustler::Error> for Error {
    fn from(error: rustler::Error) -> Self {
        Error::Rustler(error)
    }
}
impl From<yrs::TransactionAcqError> for Error {
    fn from(_: yrs::TransactionAcqError) -> Self {
        Error::Transaction
    }
}

impl From<Error> for rustler::Error {
    fn from(error: Error) -> rustler::Error {
        match error {
            Error::Transaction => rustler::Error::RaiseTerm(Box::new(TransactionAcqError::new())),
            Error::Encoding(error) => {
                rustler::Error::Term(Box::new((atoms::encoding_exception(), error.to_string())))
            }
            Error::Update(error) => rustler::Error::Term(Box::new(error.to_string())),
            Error::Awareness(error) => rustler::Error::Term(Box::new(error.to_string())),
            Error::Message(error) => rustler::Error::Term(Box::new(error)),
            Error::Rustler(error) => error,
        }
    }
}
