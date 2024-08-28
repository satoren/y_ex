use std::cell::RefCell;
use std::ops::Deref;
use std::sync::Mutex;

use crate::subscription::SubscriptionResource;
use crate::wrap::encode_binary_slice_to_term;
use crate::xml::NifXmlFragment;
use crate::{atoms, ENV};
use rustler::{Binary, Env, LocalPid, NifStruct, NifUnitEnum, ResourceArc, Term};
use yrs::updates::decoder::Decode;
use yrs::updates::encoder::Encode;
use yrs::*;

use crate::{wrap::NifWrap, NifArray, NifError, NifMap, NifText};
pub struct DocInner {
    pub doc: Doc,
}

pub type DocResource = NifWrap<DocInner>;

impl DocInner {
    pub fn mutably<F, T>(
        &self,
        env: Env<'_>,
        current_transaction: Option<ResourceArc<TransactionResource>>,
        f: F,
    ) -> Result<T, NifError>
    where
        F: FnOnce(&mut TransactionMut<'_>) -> Result<T, NifError>,
    {
        ENV.set(&mut env.clone(), || {
            if let Some(txn) = current_transaction {
                if let Some(txn) = txn.0.borrow_mut().as_mut() {
                    f(txn)
                } else {
                    f(&mut yrs::Transact::transact_mut(&self.doc))
                }
            } else {
                f(&mut yrs::Transact::transact_mut(&self.doc))
            }
        })
    }

    pub fn readonly<F, T>(
        &self,
        current_transaction: Option<ResourceArc<TransactionResource>>,
        f: F,
    ) -> T
    where
        F: FnOnce(&ReadTransaction) -> T,
    {
        // TODO:
        if let Some(txn) = current_transaction {
            if let Some(txn) = txn.0.borrow_mut().as_ref() {
                txn.store();
                f(&ReadTransaction::ReadWrite(txn))
            } else {
                f(&ReadTransaction::ReadOnly(&yrs::Transact::transact(
                    &self.doc,
                )))
            }
        } else {
            f(&ReadTransaction::ReadOnly(&yrs::Transact::transact(
                &self.doc,
            )))
        }
    }
}

pub enum ReadTransaction<'a, 'doc> {
    ReadOnly(&'a yrs::Transaction<'doc>),
    ReadWrite(&'a yrs::TransactionMut<'doc>),
}

impl ReadTxn for ReadTransaction<'_, '_> {
    fn store(&self) -> &Store {
        match &self {
            ReadTransaction::ReadOnly(txn) => txn.store(),
            ReadTransaction::ReadWrite(txn) => txn.store(),
        }
    }
}

#[rustler::resource_impl]
impl rustler::Resource for DocResource {}

pub struct TransactionResource(pub RefCell<Option<TransactionMut<'static>>>);

unsafe impl Send for TransactionResource {}
unsafe impl Sync for TransactionResource {}

#[rustler::resource_impl]
impl rustler::Resource for TransactionResource {}

#[derive(NifUnitEnum)]
pub enum NifOffsetKind {
    Bytes,
    Utf16,
}

#[derive(NifStruct)]
#[module = "Yex.Doc.Options"]
pub struct NifOptions {
    /// Globally unique client identifier. This value must be unique across all active collaborating
    /// peers, otherwise a update collisions will happen, causing document store state to be corrupted.
    ///
    /// Default value: randomly generated.
    pub client_id: u64,
    /// A globally unique identifier for this document.
    ///
    /// Default value: randomly generated UUID v4.
    pub guid: Option<String>,
    /// Associate this document with a collection. This only plays a role if your provider has
    /// a concept of collection.
    ///
    /// Default value: `None`.
    pub collection_id: Option<String>,
    /// How to we count offsets and lengths used in text operations.
    ///
    /// Default value: [OffsetKind::Bytes].
    pub offset_kind: NifOffsetKind,
    /// Determines if transactions commits should try to perform GC-ing of deleted items.
    ///
    /// Default value: `false`.
    pub skip_gc: bool,
    /// If a subdocument, automatically load document. If this is a subdocument, remote peers will
    /// load the document as well automatically.
    ///
    /// Default value: `false`.
    pub auto_load: bool,
    /// Whether the document should be synced by the provider now.
    /// This is toggled to true when you call ydoc.load().
    ///
    /// Default value: `true`.
    pub should_load: bool,
}

impl From<NifOptions> for Options {
    fn from(w: NifOptions) -> Options {
        let offset_kind = match w.offset_kind {
            NifOffsetKind::Bytes => OffsetKind::Bytes,
            NifOffsetKind::Utf16 => OffsetKind::Utf16,
        };
        let guid = if let Some(id) = w.guid {
            id.into()
        } else {
            uuid_v4()
        };
        Options {
            client_id: w.client_id,
            guid,
            collection_id: w.collection_id.map(|s| s.into()),
            offset_kind,
            skip_gc: w.skip_gc,
            auto_load: w.auto_load,
            should_load: w.should_load,
        }
    }
}

#[derive(NifStruct)]
#[module = "Yex.Doc"]
pub(crate) struct NifDoc {
    pub(crate) reference: ResourceArc<DocResource>,
}
impl NifDoc {
    pub fn with_options(option: NifOptions) -> Self {
        NifDoc {
            reference: ResourceArc::new(
                DocInner {
                    doc: Doc::with_options(option.into()),
                }
                .into(),
            ),
        }
    }
    pub fn from_native(doc: Doc) -> Self {
        NifDoc {
            reference: ResourceArc::new(DocInner { doc }.into()),
        }
    }

    pub fn get_or_insert_text(&self, name: &str) -> NifText {
        NifText::new(
            self.reference.clone(),
            self.reference.doc.get_or_insert_text(name),
        )
    }
    pub fn get_or_insert_array(&self, name: &str) -> NifArray {
        NifArray::new(
            self.reference.clone(),
            self.reference.doc.get_or_insert_array(name),
        )
    }

    pub fn get_or_insert_map(&self, name: &str) -> NifMap {
        NifMap::new(
            self.reference.clone(),
            self.reference.doc.get_or_insert_map(name),
        )
    }

    pub fn get_or_insert_xml_fragment(&self, name: &str) -> NifXmlFragment {
        NifXmlFragment::new(
            self.reference.clone(),
            self.reference.doc.get_or_insert_xml_fragment(name),
        )
    }

    pub fn monitor_update_v1(
        &self,
        pid: LocalPid,
    ) -> Result<ResourceArc<SubscriptionResource>, NifError> {
        let doc_ref = self.reference.clone();
        self.observe_update_v1(move |txn, event| {
            let doc_ref = doc_ref.clone();
            ENV.with(|env| {
                let origin: Option<_> = txn.origin().map(|s| s.to_string());
                let _ = env.send(
                    &pid,
                    (
                        atoms::update_v1(),
                        encode_binary_slice_to_term(*env, event.update.as_slice()),
                        origin,
                        NifDoc { reference: doc_ref },
                    ),
                );
            })
        })
        .map(|sub| ResourceArc::new(Mutex::new(Some(sub)).into()))
        .map_err(|e| NifError {
            reason: atoms::encoding_exception(),
            message: e.to_string(),
        })
    }

    pub fn monitor_update_v2(
        &self,
        pid: LocalPid,
    ) -> Result<ResourceArc<SubscriptionResource>, NifError> {
        let doc_ref = self.reference.clone();
        self.observe_update_v2(move |txn, event| {
            let doc_ref = doc_ref.clone();
            ENV.with(|env| {
                let origin: Option<_> = txn.origin().map(|s| s.to_string());

                let _ = env.send(
                    &pid,
                    (
                        atoms::update_v2(),
                        encode_binary_slice_to_term(*env, event.update.as_slice()),
                        origin,
                        NifDoc { reference: doc_ref },
                    ),
                );
            })
        })
        .map(|sub| ResourceArc::new(Mutex::new(Some(sub)).into()))
        .map_err(|e| NifError {
            reason: atoms::encoding_exception(),
            message: e.to_string(),
        })
    }
}

impl Default for NifDoc {
    fn default() -> Self {
        NifDoc {
            reference: ResourceArc::new(DocInner { doc: Doc::new() }.into()),
        }
    }
}

impl Deref for NifDoc {
    type Target = Doc;

    fn deref(&self) -> &Self::Target {
        &self.reference.0.doc
    }
}

#[rustler::nif]
fn doc_new() -> NifDoc {
    NifDoc::default()
}

#[rustler::nif]
fn doc_with_options(option: NifOptions) -> NifDoc {
    NifDoc::with_options(option)
}

#[rustler::nif]
fn doc_get_or_insert_text(env: Env<'_>, doc: NifDoc, name: &str) -> NifText {
    ENV.set(&mut env.clone(), || doc.get_or_insert_text(name))
}

#[rustler::nif]
fn doc_get_or_insert_array(env: Env<'_>, doc: NifDoc, name: &str) -> NifArray {
    ENV.set(&mut env.clone(), || doc.get_or_insert_array(name))
}

#[rustler::nif]
fn doc_get_or_insert_map(env: Env<'_>, doc: NifDoc, name: &str) -> NifMap {
    ENV.set(&mut env.clone(), || doc.get_or_insert_map(name))
}

#[rustler::nif]
fn doc_get_or_insert_xml_fragment(env: Env<'_>, doc: NifDoc, name: &str) -> NifXmlFragment {
    ENV.set(&mut env.clone(), || doc.get_or_insert_xml_fragment(name))
}

#[rustler::nif]
fn doc_begin_transaction(doc: NifDoc, origin: Option<&str>) -> ResourceArc<TransactionResource> {
    if let Some(origin) = origin {
        let txn: TransactionMut = doc.reference.doc.try_transact_mut_with(origin).unwrap();
        let txn: TransactionMut<'static> = unsafe { std::mem::transmute(txn) };

        TransactionResource(RefCell::new(Some(txn))).into()
    } else {
        let txn: TransactionMut = doc.reference.doc.try_transact_mut().unwrap();
        let txn: TransactionMut<'static> = unsafe { std::mem::transmute(txn) };
        TransactionResource(RefCell::new(Some(txn))).into()
    }
}

#[rustler::nif]
fn commit_transaction(env: Env<'_>, current_transaction: ResourceArc<TransactionResource>) {
    ENV.set(&mut env.clone(), || {
        let mut v = current_transaction.0.borrow_mut();
        *v = None;
    })
}

#[rustler::nif]
fn doc_monitor_update_v1(
    doc: NifDoc,
    pid: LocalPid,
) -> Result<ResourceArc<SubscriptionResource>, NifError> {
    doc.monitor_update_v1(pid)
}
#[rustler::nif]
fn doc_monitor_update_v2(
    doc: NifDoc,
    pid: LocalPid,
) -> Result<ResourceArc<SubscriptionResource>, NifError> {
    doc.monitor_update_v2(pid)
}

#[rustler::nif]
fn apply_update_v1(
    env: Env<'_>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    update: Binary,
) -> Result<(), NifError> {
    let update = Update::decode_v1(update.as_slice()).map_err(|e| NifError {
        reason: atoms::encoding_exception(),
        message: e.to_string(),
    })?;

    doc.reference.mutably(env, current_transaction, |txn| {
        txn.apply_update(update);
        Ok(())
    })
}

#[rustler::nif]
fn apply_update_v2(
    env: Env<'_>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    update: Binary,
) -> Result<(), NifError> {
    let update = Update::decode_v2(update.as_slice()).map_err(|e| NifError {
        reason: atoms::encoding_exception(),
        message: e.to_string(),
    })?;

    doc.reference.mutably(env, current_transaction, |txn| {
        txn.apply_update(update);
        Ok(())
    })
}

#[rustler::nif]
fn encode_state_vector_v1(
    env: Env<'_>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> Result<Term<'_>, NifError> {
    doc.reference.readonly(current_transaction, |txn| {
        let vec = txn.state_vector().encode_v1();
        Ok(encode_binary_slice_to_term(env, vec.as_slice()))
    })
}

#[rustler::nif]
fn encode_state_as_update_v1<'a>(
    env: Env<'a>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    state_vector: Option<Binary>,
) -> Result<Term<'a>, NifError> {
    let sv = if let Some(vector) = state_vector {
        StateVector::decode_v1(vector.as_slice()).map_err(|e| NifError {
            reason: atoms::encoding_exception(),
            message: e.to_string(),
        })?
    } else {
        StateVector::default()
    };

    doc.reference
        .readonly(current_transaction, |txn| Ok(txn.encode_diff_v1(&sv)))
        .map(|vec| encode_binary_slice_to_term(env, vec.as_slice()))
}

#[rustler::nif]
fn encode_state_vector_v2(
    env: Env<'_>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> Result<Term<'_>, NifError> {
    let vec = doc
        .reference
        .readonly(current_transaction, |txn| txn.state_vector().encode_v2());
    Ok(encode_binary_slice_to_term(env, vec.as_slice()))
}
#[rustler::nif]
fn encode_state_as_update_v2<'a>(
    env: Env<'a>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    state_vector: Option<Binary>,
) -> Result<Term<'a>, NifError> {
    let sv = if let Some(vector) = state_vector {
        StateVector::decode_v2(vector.as_slice()).map_err(|e| NifError {
            reason: atoms::encoding_exception(),
            message: e.to_string(),
        })?
    } else {
        StateVector::default()
    };

    doc.reference
        .readonly(current_transaction, |txn| Ok(txn.encode_diff_v2(&sv)))
        .map(|vec| encode_binary_slice_to_term(env, vec.as_slice()))
}
