use std::collections::HashMap;

use crate::any::NifAny;
use rustler::*;
use yrs::{
    block::{ItemContent, Prelim, Unused},
    branch::{Branch, BranchPtr},
    types::TypeRef,
    Any, Array, ArrayRef, Map, MapRef, TransactionMut,
};

#[derive(NifStruct)]
#[module = "Yex.ArrayPrelim"]
pub struct NifArrayPrelim {
    list: Vec<NifYInput>,
}

#[derive(NifStruct)]
#[module = "Yex.MapPrelim"]
pub struct NifMapPrelim {
    map: HashMap<String, NifYInput>,
}

#[derive(NifUntaggedEnum)]
pub enum NifYInput {
    Any(NifAny),
    MapPrelim(NifMapPrelim),
    ArrayPrelim(NifArrayPrelim),
}

impl Prelim for NifYInput {
    type Return = Unused;

    fn into_content(self, _txn: &mut TransactionMut) -> (ItemContent, Option<Self>) {
        match self {
            NifYInput::Any(any) => {
                let value: Any = any.0;
                (ItemContent::Any(vec![value]), None)
            }
            NifYInput::MapPrelim(_) => {
                let inner = Branch::new(TypeRef::Map);
                (ItemContent::Type(inner), Some(self))
            }
            NifYInput::ArrayPrelim(_) => {
                let inner = Branch::new(TypeRef::Array);
                (ItemContent::Type(inner), Some(self))
            }
        }
    }

    fn integrate(self, txn: &mut TransactionMut, inner_ref: BranchPtr) {
        match self {
            NifYInput::Any(any) => {
                let any = any.0;
                any.integrate(txn, inner_ref);
            }
            NifYInput::MapPrelim(v) => {
                let map = MapRef::from(inner_ref);
                for (key, value) in v.map {
                    map.insert(txn, key, value);
                }
            }
            NifYInput::ArrayPrelim(v) => {
                let array = ArrayRef::from(inner_ref);
                for value in v.list {
                    array.push_back(txn, value);
                }
            }
        }
    }
}
