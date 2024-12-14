use rustler::{Atom, Decoder, Encoder, Env, NifResult, NifStruct, NifUnitEnum, ResourceArc, Term};
use serde::{Deserialize as _, Serialize as _};
use yrs::{Assoc, IndexedSequence as _, StickyIndex};

use crate::{
    atoms,
    doc::{DocResource, TransactionResource},
    shared_type::NifSharedType,
    wrap::SliceIntoBinary,
    yinput::NifSharedTypeInput,
};

pub struct StickyIndexRef(pub StickyIndex);
impl StickyIndexRef {
    pub fn new(v: StickyIndex) -> Self {
        Self(v)
    }
}

impl<'de, 'a: 'de> Encoder for StickyIndexRef {
    fn encode<'b>(&self, env: Env<'b>) -> Term<'b> {
        let mut s = flexbuffers::FlexbufferSerializer::new();

        if let Err(err) = self.0.serialize(&mut s) {
            return (atoms::error(), err.to_string()).encode(env);
        }
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
    doc: ResourceArc<DocResource>,
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

#[rustler::nif]
fn sticky_index_new(
    env: Env<'_>,
    shared_type: NifSharedTypeInput,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    index: u32,
    assoc: NifAssoc,
) -> NifResult<NifStickyIndex> {
    match shared_type {
        NifSharedTypeInput::Array(array) => array.mutably(env, current_transaction, |txn| {
            let doc = array.doc().clone();
            let array = array.get_ref(txn)?;
            let sticky_index = array
                .sticky_index(txn, index, (&assoc).into())
                .ok_or(rustler::Error::BadArg)?;
            let sticky_index = NifStickyIndex {
                doc: doc,
                reference: StickyIndexRef::new(sticky_index),
                assoc,
            };
            Ok(sticky_index)
        }),
        NifSharedTypeInput::Text(text) => text.mutably(env, current_transaction, |txn| {
            let doc = text.doc().clone();
            let text = text.get_ref(txn)?;
            let sticky_index = text
                .sticky_index(txn, index, (&assoc).into())
                .ok_or(rustler::Error::BadArg)?;
            let sticky_index = NifStickyIndex {
                doc: doc,
                reference: StickyIndexRef::new(sticky_index),
                assoc,
            };
            Ok(sticky_index)
        }),
        NifSharedTypeInput::XmlText(xml_text) => {
            xml_text.mutably(env, current_transaction, |txn| {
                let doc = xml_text.doc().clone();
                let xml_text = xml_text.get_ref(txn)?;
                let sticky_index = xml_text
                    .sticky_index(txn, index, (&assoc).into())
                    .ok_or(rustler::Error::BadArg)?;
                let sticky_index = NifStickyIndex {
                    doc: doc,
                    reference: StickyIndexRef::new(sticky_index),
                    assoc: assoc,
                };
                Ok(sticky_index)
            })
        }
        NifSharedTypeInput::XmlFragment(xml_fragment) => {
            xml_fragment.mutably(env, current_transaction, |txn| {
                let doc = xml_fragment.doc().clone();
                let xml_fragment = xml_fragment.get_ref(txn)?;
                let sticky_index = xml_fragment
                    .sticky_index(txn, index, (&assoc).into())
                    .ok_or(rustler::Error::BadArg)?;
                let sticky_index = NifStickyIndex {
                    doc: doc,
                    reference: StickyIndexRef::new(sticky_index),
                    assoc,
                };
                Ok(sticky_index)
            })
        }
        NifSharedTypeInput::XmlElement(xml_element) => {
            xml_element.mutably(env, current_transaction, |txn| {
                let doc = xml_element.doc().clone();
                let xml_element = xml_element.get_ref(txn)?;
                let sticky_index = xml_element
                    .sticky_index(txn, index, (&assoc).into())
                    .ok_or(rustler::Error::BadArg)?;
                let sticky_index = NifStickyIndex {
                    doc: doc,
                    reference: StickyIndexRef::new(sticky_index),
                    assoc,
                };
                Ok(sticky_index)
            })
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
