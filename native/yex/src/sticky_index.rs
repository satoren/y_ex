use rustler::{Atom, Decoder, Encoder, Env, NifResult, NifStruct, NifUnitEnum, ResourceArc, Term};
use serde::{Deserialize as _, Serialize as _};
use yrs::{Assoc, IndexedSequence, StickyIndex};

use crate::{
    atoms, doc::NifDoc, shared_type::NifSharedType, transaction::TransactionResource,
    utils::normalize_index, wrap::SliceIntoBinary, yinput::NifSharedTypeInput,
};

pub struct StickyIndexRef(pub StickyIndex);
impl StickyIndexRef {
    pub fn new(v: StickyIndex) -> Self {
        Self(v)
    }
}

impl Encoder for StickyIndexRef {
    fn encode<'b>(&self, env: Env<'b>) -> Term<'b> {
        let mut s = flexbuffers::FlexbufferSerializer::new();

        self.0.serialize(&mut s).expect("encode failed");
        SliceIntoBinary::new(s.view()).encode(env)
    }
}
impl<'a> Decoder<'a> for StickyIndexRef {
    fn decode(term: Term<'a>) -> NifResult<Self> {
        let bin = term.decode_as_binary()?;
        let r =
            flexbuffers::Reader::get_root(bin.as_slice()).map_err(|_e| rustler::Error::BadArg)?;
        let hook = StickyIndex::deserialize(r).map_err(|_e| rustler::Error::BadArg)?;
        Ok(StickyIndexRef::new(hook))
    }
}

#[derive(NifStruct)]
#[module = "Yex.StickyIndex"]
pub struct NifStickyIndex {
    doc: NifDoc,
    reference: StickyIndexRef,
    assoc: NifAssoc,
}
#[derive(NifUnitEnum)]
enum NifAssoc {
    After,
    Before,
}

impl From<Assoc> for NifAssoc {
    fn from(v: Assoc) -> NifAssoc {
        match v {
            Assoc::After => NifAssoc::After,
            Assoc::Before => NifAssoc::Before,
        }
    }
}

impl From<&NifAssoc> for Assoc {
    fn from(v: &NifAssoc) -> Assoc {
        match v {
            NifAssoc::After => Assoc::After,
            NifAssoc::Before => Assoc::Before,
        }
    }
}
impl From<&NifStickyIndex> for StickyIndex {
    fn from(val: &NifStickyIndex) -> Self {
        val.reference.0.clone()
    }
}

fn create_sticky_index<T>(
    shared_type: &T,
    env: Env<'_>,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: i64,
    assoc: NifAssoc,
) -> NifResult<NifStickyIndex>
where
    T: NifSharedType,
    T::RefType: IndexedSequence,
{
    shared_type.mutably(env, current_transaction, |txn| {
        let doc = shared_type.doc().clone();
        let shared_ref = shared_type.get_ref(txn)?;
        let len = shared_ref.as_ref().len();
        let index = normalize_index(len, index);
        let sticky_index = shared_ref
            .sticky_index(txn, index, (&assoc).into())
            .ok_or(rustler::Error::BadArg)?;
        Ok(NifStickyIndex {
            doc,
            reference: StickyIndexRef::new(sticky_index),
            assoc,
        })
    })
}

#[rustler::nif]
fn sticky_index_new(
    env: Env<'_>,
    shared_type: NifSharedTypeInput,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: i64,
    assoc: NifAssoc,
) -> NifResult<NifStickyIndex> {
    match shared_type {
        NifSharedTypeInput::Array(array) => {
            create_sticky_index(&array, env, current_transaction, index, assoc)
        }
        NifSharedTypeInput::Text(text) => {
            create_sticky_index(&text, env, current_transaction, index, assoc)
        }
        NifSharedTypeInput::XmlText(xml_text) => {
            create_sticky_index(&xml_text, env, current_transaction, index, assoc)
        }
        NifSharedTypeInput::XmlFragment(xml_fragment) => {
            create_sticky_index(&xml_fragment, env, current_transaction, index, assoc)
        }
        NifSharedTypeInput::XmlElement(xml_element) => {
            create_sticky_index(&xml_element, env, current_transaction, index, assoc)
        }
        _ => Err(rustler::Error::BadArg),
    }
}

#[derive(rustler::NifMap)]
struct NifOffset {
    pub index: u32,
    pub assoc: NifAssoc,
}

#[rustler::nif]
fn sticky_index_get_offset(
    sticky_index: NifStickyIndex,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<(Atom, NifOffset)> {
    let doc = sticky_index.doc.clone();

    doc.readonly(current_transaction, |txn| {
        let sticky_index = sticky_index.reference.0;
        match sticky_index.get_offset(txn) {
            Some(offset) => Ok((
                atoms::ok(),
                NifOffset {
                    index: offset.index,
                    assoc: offset.assoc.into(),
                },
            )),
            None => Err(rustler::Error::Atom("error")),
        }
    })
}
