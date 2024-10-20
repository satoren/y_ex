use rustler::{Atom, NifUntaggedEnum};

#[derive(NifUntaggedEnum)]
pub enum NifError {
    AtomTuple((Atom, String)),
    Message(String),
}

impl From<yrs::encoding::read::Error> for NifError {
    fn from(w: yrs::encoding::read::Error) -> NifError {
        NifError::Message(w.to_string())
    }
}

impl From<rustler::Error> for NifError {
    fn from(_w: rustler::Error) -> NifError {
        NifError::Message("todo".to_string())
    }
}
