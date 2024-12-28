use crate::atoms;

#[derive(Debug)]
pub enum Error {
    TransactionError,
    UpdateError(yrs::error::UpdateError),
    EncodingError(yrs::encoding::read::Error),
    AwarenessError(yrs::sync::awareness::Error),
    RustlerError(rustler::Error),
    Message(String),
}

impl rustler::Encoder for Error {
    fn encode<'a>(&self, env: rustler::Env<'a>) -> rustler::Term<'a> {
        match self {
            Error::TransactionError => atoms::transaction_acq_error().encode(env),
            Error::EncodingError(error) => (
                atoms::error(),
                (atoms::encoding_exception(), error.to_string()),
            )
                .encode(env),
            Error::UpdateError(error) => (atoms::error(), error.to_string()).encode(env),
            Error::AwarenessError(error) => (atoms::error(), error.to_string()).encode(env),
            Error::Message(error) => (atoms::error(), error).encode(env),
            Error::RustlerError(_) => panic!("RustlerError not supported"),
        }
    }
}

impl From<yrs::error::UpdateError> for Error {
    fn from(error: yrs::error::UpdateError) -> Self {
        Error::UpdateError(error)
    }
}
impl From<yrs::encoding::read::Error> for Error {
    fn from(error: yrs::encoding::read::Error) -> Self {
        Error::EncodingError(error)
    }
}
impl From<yrs::sync::awareness::Error> for Error {
    fn from(error: yrs::sync::awareness::Error) -> Self {
        Error::AwarenessError(error)
    }
}
impl From<rustler::Error> for Error {
    fn from(error: rustler::Error) -> Self {
        Error::RustlerError(error)
    }
}
impl From<yrs::TransactionAcqError> for Error {
    fn from(_: yrs::TransactionAcqError) -> Self {
        Error::TransactionError
    }
}

impl From<Error> for rustler::Error {
    fn from(error: Error) -> rustler::Error {
        match error {
            Error::TransactionError => rustler::Error::Atom("transaction_acq_error"),
            Error::EncodingError(error) => {
                rustler::Error::Term(Box::new((atoms::encoding_exception(), error.to_string())))
            }
            Error::UpdateError(error) => rustler::Error::Term(Box::new(error.to_string())),
            Error::AwarenessError(error) => rustler::Error::Term(Box::new(error.to_string())),
            Error::Message(error) => rustler::Error::Term(Box::new(error)),
            Error::RustlerError(error) => error,
        }
    }
}
