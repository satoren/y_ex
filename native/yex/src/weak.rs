use crate::doc::NifDoc;
use crate::event::{NifSharedTypeDeepObservable, NifSharedTypeObservable, NifWeakLinkEvent};
use crate::shared_type::{NifSharedType, SharedTypeId};
use crate::transaction::TransactionResource;
use crate::yinput::NifWeakPrelim;
use crate::youtput::NifYOut;

use rustler::{NifResult, NifStruct, ResourceArc};
use yrs::branch::BranchPtr;
use yrs::types::AsPrelim;
use yrs::*;

pub type WeakLinkRefId = SharedTypeId<WeakRef<BranchPtr>>;

#[derive(NifStruct)]
#[module = "Yex.WeakLink"]
pub struct NifWeakLink {
    doc: NifDoc,
    reference: WeakLinkRefId,
}

impl NifWeakLink {
    pub fn new(doc: NifDoc, weak: WeakRef<BranchPtr>) -> Self {
        NifWeakLink {
            doc,
            reference: WeakLinkRefId::new(weak.hook()),
        }
    }
}

impl NifSharedType for NifWeakLink {
    type RefType = WeakRef<BranchPtr>;

    fn doc(&self) -> &NifDoc {
        &self.doc
    }
    fn reference(&self) -> &SharedTypeId<Self::RefType> {
        &self.reference
    }
    const DELETED_ERROR: &'static str = "WeakLink has been deleted";
}

impl NifSharedTypeDeepObservable for NifWeakLink {}
impl NifSharedTypeObservable for NifWeakLink {
    type Event = NifWeakLinkEvent;
}

#[rustler::nif]
fn weak_string(
    weak: NifWeakLink,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<String> {
    weak.readonly(current_transaction, |txn| {
        let weak_ref = weak.get_ref(txn)?;
        let a: WeakRef<TextRef> = weak_ref.into();

        Ok(a.get_string(txn))
    })
}

#[rustler::nif]
fn weak_unquote(
    weak: NifWeakLink,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<Vec<NifYOut>> {
    weak.readonly(current_transaction, |txn| {
        let weak_ref = weak.get_ref(txn)?;
        let a: WeakRef<ArrayRef> = weak_ref.into();
        let doc = weak.doc.clone();
        let unquoted: Vec<NifYOut> = a
            .unquote(txn)
            .map(|v| NifYOut::from_native(v, doc.clone()))
            .collect();
        Ok(unquoted)
    })
}

#[rustler::nif]
fn weak_deref(
    weak: NifWeakLink,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<Option<NifYOut>> {
    weak.readonly(current_transaction, |txn| {
        let weak_ref = weak.get_ref(txn)?;
        let a: WeakRef<MapRef> = weak_ref.into();

        let doc = weak.doc.clone();
        let value: Option<NifYOut> = a.try_deref_value(txn).map(|v| NifYOut::from_native(v, doc));
        Ok(value)
    })
}

#[rustler::nif]
fn weak_as_prelim(
    weak: NifWeakLink,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<NifWeakPrelim> {
    weak.readonly(current_transaction, |txn| {
        let weak_ref = weak.get_ref(txn)?;
        let prelim = weak_ref.as_prelim(txn);
        let value = NifWeakPrelim::new(prelim.upcast());
        Ok(value)
    })
}
