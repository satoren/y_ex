use std::cell::RefCell;
use std::ops::Deref;

use crate::subscription::SubscriptionResource;
use crate::wrap::encode_binary_slice_to_term;
use crate::{atoms, ENV};
use rustler::{Env, LocalPid, NifStruct, NifUnitEnum, ResourceArc};
use yrs::updates::decoder::Decode;
use yrs::updates::encoder::Encode;
use yrs::*;

use crate::{wrap::NifWrap, NifArray, NifError, NifMap, NifText};
pub struct DocInner {
    pub doc: Doc,
    pub(crate) current_transaction: RefCell<Option<TransactionMut<'static>>>,
}

pub type DocResource = NifWrap<DocInner>;

impl DocInner {
    pub fn mutably<F, T>(&self, f: F) -> Result<T, NifError>
    where
        F: FnOnce(&mut TransactionMut<'_>) -> Result<T, NifError>,
    {
        if let Some(txn) = self.current_transaction.borrow_mut().as_mut() {
            f(txn)
        } else {
            let mut txn = self.doc.transact_mut();
            f(&mut txn)
        }
    }

    pub fn readonly<F, T>(&self, f: F) -> T
    where
        F: FnOnce(&TransactionMut<'_>) -> T,
    {
        if let Some(txn) = self.current_transaction.borrow_mut().as_ref() {
            f(txn)
        } else {
            let txn = self.doc.transact_mut();
            f(&txn)
        }
    }
}

#[rustler::resource_impl]
impl rustler::Resource for DocResource {}

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
            collection_id: w.collection_id,
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
                    current_transaction: RefCell::new(None),
                }
                .into(),
            ),
        }
    }
    pub fn from_native(doc: Doc) -> Self {
        NifDoc {
            reference: ResourceArc::new(
                DocInner {
                    doc,
                    current_transaction: RefCell::new(None),
                }
                .into(),
            ),
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

    pub fn begin_transaction(&self) -> Result<(), NifError> {
        let txn: TransactionMut = self.reference.doc.transact_mut();
        let txn: TransactionMut<'static> = unsafe { std::mem::transmute(txn) };
        *self.reference.current_transaction.borrow_mut() = Some(txn);
        Ok(())
    }
    pub fn begin_transaction_with(&self, origin: &str) -> Result<(), NifError> {
        let txn: TransactionMut = self.reference.doc.transact_mut_with(origin);
        let txn: TransactionMut<'static> = unsafe { std::mem::transmute(txn) };
        *self.reference.current_transaction.borrow_mut() = Some(txn);
        Ok(())
    }

    pub fn commit_transaction(&self) {
        *self.reference.current_transaction.borrow_mut() = None;
    }

    pub fn encode_state_vector_v1(&self) -> Result<Vec<u8>, NifError> {
        if let Some(txn) = self.reference.current_transaction.borrow_mut().as_mut() {
            Ok(txn.state_vector().encode_v1())
        } else {
            let txn = self.reference.doc.transact();

            Ok(txn.state_vector().encode_v1())
        }
    }
    pub fn encode_state_as_update_v1(
        &self,
        state_vector: Option<&[u8]>,
    ) -> Result<Vec<u8>, NifError> {
        let sv = if let Some(vector) = state_vector {
            StateVector::decode_v1(vector).map_err(|e| NifError {
                reason: atoms::encoding_exception(),
                message: e.to_string(),
            })?
        } else {
            StateVector::default()
        };

        self.reference.readonly(|txn| Ok(txn.encode_diff_v1(&sv)))
    }
    pub fn apply_update_v1(&self, update: &[u8]) -> Result<(), NifError> {
        let update = Update::decode_v1(update).map_err(|e| NifError {
            reason: atoms::encoding_exception(),
            message: e.to_string(),
        })?;

        self.reference.mutably(|txn| {
            txn.apply_update(update);
            Ok(())
        })
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
        .map(|sub| ResourceArc::new(RefCell::new(Some(sub)).into()))
        .map_err(|e| NifError {
            reason: atoms::encoding_exception(),
            message: e.to_string(),
        })
    }
    pub fn encode_state_vector_v2(&self) -> Result<Vec<u8>, NifError> {
        self.reference
            .readonly(|txn| Ok(txn.state_vector().encode_v2()))
    }
    pub fn encode_state_as_update_v2(
        &self,
        state_vector: Option<&[u8]>,
    ) -> Result<Vec<u8>, NifError> {
        let sv = if let Some(vector) = state_vector {
            StateVector::decode_v2(vector).map_err(|e| NifError {
                reason: atoms::encoding_exception(),
                message: e.to_string(),
            })?
        } else {
            StateVector::default()
        };

        self.reference.mutably(|txn| Ok(txn.encode_diff_v2(&sv)))
    }
    pub fn apply_update_v2(&self, update: &[u8]) -> Result<(), NifError> {
        let update = Update::decode_v2(update).map_err(|e| NifError {
            reason: atoms::encoding_exception(),
            message: e.to_string(),
        })?;

        self.reference.mutably(|txn| {
            txn.apply_update(update);
            Ok(())
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
        .map(|sub| ResourceArc::new(RefCell::new(Some(sub)).into()))
        .map_err(|e| NifError {
            reason: atoms::encoding_exception(),
            message: e.to_string(),
        })
    }
}

impl Default for NifDoc {
    fn default() -> Self {
        NifDoc {
            reference: ResourceArc::new(
                DocInner {
                    doc: Doc::new(),
                    current_transaction: RefCell::new(None),
                }
                .into(),
            ),
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
fn doc_begin_transaction(doc: NifDoc, origin: Option<&str>) -> Result<(), NifError> {
    if let Some(origin) = origin {
        doc.begin_transaction_with(origin)
    } else {
        doc.begin_transaction()
    }
}

#[rustler::nif]
fn doc_commit_transaction(env: Env<'_>, doc: NifDoc) {
    ENV.set(&mut env.clone(), || doc.commit_transaction())
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
