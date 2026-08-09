use std::collections::{HashMap, HashSet};
// Standard library imports
use std::ops::Deref;
use std::sync::{Mutex, RwLock};

// External crates
use rustler::{
    Atom, Binary, Decoder, Encoder, Env, LocalPid, NifResult, NifStruct, NifUnitEnum, ResourceArc,
    Term,
};
use yrs::updates::{
    decoder::Decode,
    encoder::{Encode, Encoder as UpdatesEncoder, EncoderV1, EncoderV2},
};
use yrs::*;

use crate::event::NifSubdocsEvent;
// Internal imports
use crate::{
    atoms,
    error::Error,
    subscription::NifSubscription,
    term_box::TermBox,
    transaction::{ReadTransaction, TransactionResource},
    utils::{origin_to_term, term_to_origin_binary},
    wrap::SliceIntoBinary,
    xml::NifXmlFragment,
    youtput::NifYOut,
    NifArray, NifMap, NifText, ENV,
};

pub(crate) struct DocResource {
    pub(crate) doc: Doc,
    pub(crate) subdocs: Mutex<HashMap<String, ResourceArc<DocResource>>>,
}

impl std::ops::Deref for DocResource {
    type Target = Doc;

    fn deref(&self) -> &Self::Target {
        &self.doc
    }
}

impl std::panic::RefUnwindSafe for DocResource {}

pub struct SnapshotRef(pub Snapshot);

impl SnapshotRef {
    pub fn new(v: Snapshot) -> Self {
        Self(v)
    }
}

impl Encoder for SnapshotRef {
    fn encode<'b>(&self, env: Env<'b>) -> Term<'b> {
        let encoded = self.0.encode_v1();
        SliceIntoBinary::new(encoded.as_slice()).encode(env)
    }
}

impl<'a> Decoder<'a> for SnapshotRef {
    fn decode(term: Term<'a>) -> NifResult<Self> {
        let bin = term.decode_as_binary()?;
        let snapshot = Snapshot::decode_v1(bin.as_slice()).map_err(Error::from)?;
        Ok(SnapshotRef::new(snapshot))
    }
}

#[derive(NifStruct)]
#[module = "Yex.Snapshot"]
pub struct NifSnapshot {
    pub doc: NifDoc,
    pub reference: SnapshotRef,
}

#[rustler::resource_impl]
impl rustler::Resource for DocResource {}

#[derive(NifUnitEnum)]
pub enum NifOffsetKind {
    Bytes,
    Utf16,
}

impl From<OffsetKind> for NifOffsetKind {
    fn from(offset_kind: OffsetKind) -> Self {
        match offset_kind {
            OffsetKind::Bytes => NifOffsetKind::Bytes,
            OffsetKind::Utf16 => NifOffsetKind::Utf16,
        }
    }
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

#[derive(NifStruct, Clone)]
#[module = "Yex.Doc"]
pub(crate) struct NifDoc {
    pub(crate) reference: ResourceArc<DocResource>,
    pub(crate) worker_pid: Option<LocalPid>,
}

impl Default for NifDoc {
    fn default() -> Self {
        NifDoc {
            reference: ResourceArc::new(DocResource {
                doc: Doc::new(),
                subdocs: Mutex::new(HashMap::new()),
            }),
            worker_pid: None,
        }
    }
}
impl NifDoc {
    pub fn with_options(option: NifOptions) -> Self {
        NifDoc {
            reference: ResourceArc::new(DocResource {
                doc: Doc::with_options(option.into()),
                subdocs: Mutex::new(HashMap::new()),
            }),
            worker_pid: None,
        }
    }

    fn prune_subdoc_cache(
        &self,
        cache: &mut HashMap<String, ResourceArc<DocResource>>,
        keep_guid: &str,
        active_subdoc_guids: Option<&HashSet<String>>,
    ) {
        if let Some(active_guids) = active_subdoc_guids {
            cache.retain(|guid, _| guid == keep_guid || active_guids.contains(guid));
        }
    }

    fn cached_subdoc_reference(
        &self,
        subdoc: Doc,
        cache_on_miss: bool,
        active_subdoc_guids: Option<&HashSet<String>>,
    ) -> ResourceArc<DocResource> {
        let subdoc_guid = subdoc.guid().to_string();

        if let Ok(mut cache) = self.reference.subdocs.lock() {
            self.prune_subdoc_cache(&mut cache, &subdoc_guid, active_subdoc_guids);

            if let Some(reference) = cache.get(&subdoc_guid) {
                return reference.clone();
            }

            let reference: ResourceArc<DocResource> = ResourceArc::new(DocResource {
                doc: subdoc,
                subdocs: Mutex::new(HashMap::new()),
            });
            if cache_on_miss {
                cache.insert(subdoc_guid, reference.clone());
            }
            reference
        } else {
            ResourceArc::new(DocResource {
                doc: subdoc,
                subdocs: Mutex::new(HashMap::new()),
            })
        }
    }

    pub fn with_cached_subdoc(
        &self,
        subdoc: Doc,
        active_subdoc_guids: Option<&HashSet<String>>,
    ) -> Self {
        NifDoc {
            reference: self.cached_subdoc_reference(subdoc, true, active_subdoc_guids),
            worker_pid: self.worker_pid,
        }
    }

    pub fn with_subdoc_reference(
        &self,
        subdoc: Doc,
        active_subdoc_guids: Option<&HashSet<String>>,
    ) -> Self {
        NifDoc {
            reference: self.cached_subdoc_reference(subdoc, false, active_subdoc_guids),
            worker_pid: self.worker_pid,
        }
    }

    pub fn get_or_insert_text(&self, name: &str) -> NifText {
        NifText::new(self.clone(), self.reference.get_or_insert_text(name))
    }
    pub fn get_or_insert_array(&self, name: &str) -> NifArray {
        NifArray::new(self.clone(), self.reference.get_or_insert_array(name))
    }

    pub fn get_or_insert_map(&self, name: &str) -> NifMap {
        NifMap::new(self.clone(), self.reference.get_or_insert_map(name))
    }

    pub fn get_or_insert_xml_fragment(&self, name: &str) -> NifXmlFragment {
        NifXmlFragment::new(
            self.clone(),
            self.reference.get_or_insert_xml_fragment(name),
        )
    }

    pub fn mutably<F, T>(
        &self,
        env: Env<'_>,
        current_transaction: Option<ResourceArc<TransactionResource>>,
        f: F,
    ) -> NifResult<T>
    where
        F: FnOnce(&mut TransactionMut<'_>) -> NifResult<T>,
    {
        ENV.set(&mut env.clone(), || match current_transaction {
            Some(txn) => {
                if let Ok(mut txn_guard) = txn.0.write() {
                    match txn_guard.as_mut() {
                        Some(txn) => f(txn),
                        None => self.with_transaction_mut(f),
                    }
                } else {
                    self.with_transaction_mut(f)
                }
            }
            None => self.with_transaction_mut(f),
        })
    }

    pub fn readonly<F, T>(
        &self,
        current_transaction: Option<ResourceArc<TransactionResource>>,
        f: F,
    ) -> NifResult<T>
    where
        F: FnOnce(&ReadTransaction) -> NifResult<T>,
    {
        match current_transaction {
            Some(txn) => {
                if let Ok(txn_guard) = txn.0.read() {
                    match txn_guard.as_ref() {
                        Some(txn) => f(&ReadTransaction::ReadWrite(txn)),
                        None => self.with_transaction(|txn| f(&ReadTransaction::ReadOnly(txn))),
                    }
                } else {
                    self.with_transaction(|txn| f(&ReadTransaction::ReadOnly(txn)))
                }
            }
            None => self.with_transaction(|txn| f(&ReadTransaction::ReadOnly(txn))),
        }
    }
}

impl Deref for NifDoc {
    type Target = Doc;

    fn deref(&self) -> &Self::Target {
        &self.reference.doc
    }
}

pub trait DocOperations {
    fn with_transaction<F, T>(&self, f: F) -> NifResult<T>
    where
        F: FnOnce(&Transaction) -> NifResult<T>;

    fn with_transaction_mut<F, T>(&self, f: F) -> NifResult<T>
    where
        F: FnOnce(&mut TransactionMut) -> NifResult<T>;
}

impl DocOperations for NifDoc {
    fn with_transaction<F, T>(&self, f: F) -> NifResult<T>
    where
        F: FnOnce(&Transaction) -> NifResult<T>,
    {
        let txn = yrs::Transact::try_transact(&self.reference.doc).map_err(Error::from)?;
        f(&txn)
    }

    fn with_transaction_mut<F, T>(&self, f: F) -> NifResult<T>
    where
        F: FnOnce(&mut TransactionMut) -> NifResult<T>,
    {
        let mut txn = yrs::Transact::try_transact_mut(&self.reference.doc).map_err(Error::from)?;
        f(&mut txn)
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
fn doc_begin_transaction(
    doc: NifDoc,
    origin: Term<'_>,
) -> NifResult<ResourceArc<TransactionResource>> {
    if let Some(origin) = term_to_origin_binary(origin) {
        let txn: TransactionMut =
            yrs::Transact::try_transact_mut_with(&doc.reference.doc, origin.as_slice())
                .map_err(Error::from)?;
        let txn: TransactionMut<'static> = unsafe { std::mem::transmute(txn) };

        Ok(TransactionResource(RwLock::new(Some(txn))).into())
    } else {
        let txn: TransactionMut =
            yrs::Transact::try_transact_mut(&doc.reference.doc).map_err(Error::from)?;
        let txn: TransactionMut<'static> = unsafe { std::mem::transmute(txn) };
        Ok(TransactionResource(RwLock::new(Some(txn))).into())
    }
}

#[rustler::nif]
fn commit_transaction(env: Env<'_>, current_transaction: ResourceArc<TransactionResource>) {
    ENV.set(&mut env.clone(), || {
        if let Ok(mut txn) = current_transaction.0.write() {
            *txn = None;
        }
    })
}

#[rustler::nif]
fn doc_monitor_update_v1(
    doc: NifDoc,
    pid: LocalPid,
    metadata: Term<'_>,
) -> NifResult<(Atom, NifSubscription)> {
    let metadata = TermBox::new(metadata);

    doc.observe_update_v1(move |txn, event| {
        ENV.with(|env| {
            let metadata = metadata.get(*env);
            let _ = env.send(
                &pid,
                (
                    atoms::update_v1(),
                    SliceIntoBinary::new(event.update.as_slice()),
                    origin_to_term(env, txn.origin()),
                    metadata,
                ),
            );
        })
    })
    .map(|sub| {
        (
            atoms::ok(),
            NifSubscription {
                reference: ResourceArc::new(Mutex::new(Some(sub)).into()),
                doc: doc.clone(),
            },
        )
    })
    .map_err(|e| Error::from(e).into())
}
#[rustler::nif]
fn doc_monitor_update_v2(
    doc: NifDoc,
    pid: LocalPid,
    metadata: Term<'_>,
) -> NifResult<(Atom, NifSubscription)> {
    let metadata = TermBox::new(metadata);
    doc.observe_update_v2(move |txn, event| {
        ENV.with(|env| {
            let metadata = metadata.get(*env);
            let _ = env.send(
                &pid,
                (
                    atoms::update_v2(),
                    SliceIntoBinary::new(event.update.as_slice()),
                    origin_to_term(env, txn.origin()),
                    metadata,
                ),
            );
        })
    })
    .map(|sub| {
        (
            atoms::ok(),
            NifSubscription {
                reference: ResourceArc::new(Mutex::new(Some(sub)).into()),
                doc: doc.clone(),
            },
        )
    })
    .map_err(|e| Error::from(e).into())
}

#[rustler::nif]
fn apply_update_v1(
    env: Env<'_>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    update: Binary,
) -> NifResult<Atom> {
    let update = Update::decode_v1(update.as_slice()).map_err(Error::from)?;

    doc.mutably(env, current_transaction, |txn| {
        txn.apply_update(update)
            .map(|_| atoms::ok())
            .map_err(|e| Error::from(e).into())
    })
}

#[rustler::nif]
fn apply_update_v2(
    env: Env<'_>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    update: Binary,
) -> NifResult<Atom> {
    let update = Update::decode_v2(update.as_slice()).map_err(|e| {
        rustler::Error::Term(Box::new((atoms::encoding_exception(), e.to_string())))
    })?;

    doc.mutably(env, current_transaction, |txn| {
        txn.apply_update(update)
            .map(|_| atoms::ok())
            .map_err(|e| Error::from(e).into())
    })
}

#[rustler::nif]
fn merge_updates_v1<'a>(env: Env<'a>, updates: Vec<Binary<'a>>) -> NifResult<Term<'a>> {
    let merged =
        yrs::merge_updates_v1(updates.iter().map(Binary::as_slice)).map_err(Error::from)?;
    Ok((atoms::ok(), SliceIntoBinary::new(merged.as_slice())).encode(env))
}

#[rustler::nif]
fn merge_updates_v2<'a>(env: Env<'a>, updates: Vec<Binary<'a>>) -> NifResult<Term<'a>> {
    let merged =
        yrs::merge_updates_v2(updates.iter().map(Binary::as_slice)).map_err(Error::from)?;
    Ok((atoms::ok(), SliceIntoBinary::new(merged.as_slice())).encode(env))
}

#[rustler::nif]
fn update_debug_v1<'a>(env: Env<'a>, update: Binary<'a>) -> NifResult<Term<'a>> {
    let update = Update::decode_v1(update.as_slice()).map_err(Error::from)?;
    Ok((atoms::ok(), format!("{:#?}", update)).encode(env))
}

#[rustler::nif]
fn update_debug_v2<'a>(env: Env<'a>, update: Binary<'a>) -> NifResult<Term<'a>> {
    let update = Update::decode_v2(update.as_slice()).map_err(Error::from)?;
    Ok((atoms::ok(), format!("{:#?}", update)).encode(env))
}

#[rustler::nif]
fn encode_state_vector_v1(
    env: Env<'_>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<Term<'_>> {
    doc.readonly(current_transaction, |txn| {
        let vec = txn.state_vector().encode_v1();
        Ok((atoms::ok(), SliceIntoBinary::new(vec.as_slice())).encode(env))
    })
}

#[rustler::nif]
fn encode_state_as_update_v1<'a>(
    env: Env<'a>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    state_vector: Option<Binary>,
) -> NifResult<Term<'a>> {
    let sv = if let Some(vector) = state_vector {
        StateVector::decode_v1(vector.as_slice()).map_err(Error::from)?
    } else {
        StateVector::default()
    };

    doc.readonly(current_transaction, |txn| Ok(txn.encode_diff_v1(&sv)))
        .map(|vec| (atoms::ok(), SliceIntoBinary::new(vec.as_slice())).encode(env))
}

/// Single read transaction for sync step1 response: missing diff vs remote SV + local encoded SV.
#[rustler::nif]
fn encode_diff_and_state_vector_v1<'a>(
    env: Env<'a>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    remote_state_vector: Binary<'a>,
) -> NifResult<Term<'a>> {
    let sv = StateVector::decode_v1(remote_state_vector.as_slice()).map_err(Error::from)?;
    let (diff, local_sv) = doc.readonly(current_transaction, |txn| {
        let diff = txn.encode_diff_v1(&sv);
        let local_sv = txn.state_vector().encode_v1();
        Ok((diff, local_sv))
    })?;
    Ok((
        atoms::ok(),
        SliceIntoBinary::new(diff.as_slice()),
        SliceIntoBinary::new(local_sv.as_slice()),
    )
        .encode(env))
}

#[rustler::nif]
fn encode_state_vector_v2(
    env: Env<'_>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<Term<'_>> {
    let vec = doc.readonly(current_transaction, |txn| {
        Ok(txn.state_vector().encode_v2())
    })?;
    Ok((atoms::ok(), SliceIntoBinary::new(vec.as_slice())).encode(env))
}
#[rustler::nif]
fn encode_state_as_update_v2<'a>(
    env: Env<'a>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    state_vector: Option<Binary>,
) -> NifResult<Term<'a>> {
    let sv = if let Some(vector) = state_vector {
        StateVector::decode_v2(vector.as_slice()).map_err(Error::from)?
    } else {
        StateVector::default()
    };

    let vec = doc.readonly(current_transaction, |txn| Ok(txn.encode_diff_v2(&sv)))?;

    Ok((atoms::ok(), SliceIntoBinary::new(vec.as_slice())).encode(env))
}

#[rustler::nif]
fn get_pending_update_v1<'a>(
    env: Env<'a>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<Term<'a>> {
    doc.readonly(current_transaction, |txn| {
        let result = txn.store().pending_update().map(|p| {
            let bytes = p.update.encode_v1();
            SliceIntoBinary::new(bytes.as_slice()).encode(env)
        });
        Ok((atoms::ok(), result).encode(env))
    })
}

#[rustler::nif]
fn get_pending_ds_v1<'a>(
    env: Env<'a>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<Term<'a>> {
    doc.readonly(current_transaction, |txn| {
        let result = txn.store().pending_ds().map(|ds| {
            let bytes = ds.encode_v1();
            SliceIntoBinary::new(bytes.as_slice()).encode(env)
        });
        Ok((atoms::ok(), result).encode(env))
    })
}

#[rustler::nif]
fn transaction_snapshot<'a>(
    env: Env<'a>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<Term<'a>> {
    let snapshot = doc.readonly(current_transaction, |txn| Ok(txn.snapshot()))?;

    Ok((
        atoms::ok(),
        NifSnapshot {
            doc,
            reference: SnapshotRef::new(snapshot),
        },
    )
        .encode(env))
}

#[rustler::nif]
fn transaction_encode_state_from_snapshot_v1<'a>(
    env: Env<'a>,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    snapshot: NifSnapshot,
) -> NifResult<Term<'a>> {
    let update: Vec<u8> = snapshot.doc.readonly(current_transaction, |txn| {
        let mut encoder = EncoderV1::new();
        txn.encode_state_from_snapshot(&snapshot.reference.0, &mut encoder)
            .map_err(|e| {
                rustler::Error::Term(Box::new((atoms::encoding_exception(), e.to_string())))
            })?;
        Ok(encoder.to_vec())
    })?;

    Ok((atoms::ok(), SliceIntoBinary::new(update.as_slice())).encode(env))
}

#[rustler::nif]
fn transaction_encode_state_from_snapshot_v2<'a>(
    env: Env<'a>,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    snapshot: NifSnapshot,
) -> NifResult<Term<'a>> {
    let update: Vec<u8> = snapshot.doc.readonly(current_transaction, |txn| {
        let mut encoder = EncoderV2::new();
        txn.encode_state_from_snapshot(&snapshot.reference.0, &mut encoder)
            .map_err(|e| {
                rustler::Error::Term(Box::new((atoms::encoding_exception(), e.to_string())))
            })?;
        Ok(encoder.to_vec())
    })?;

    Ok((atoms::ok(), SliceIntoBinary::new(update.as_slice())).encode(env))
}

#[rustler::nif]
fn transaction_json_path_all<'a>(
    env: Env<'a>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    path: &str,
) -> NifResult<Term<'a>> {
    let query = JsonPath::parse(path)
        .map_err(|e| rustler::Error::Term(Box::new((atoms::invalid_json_path(), e.to_string()))))?;

    let values = doc.readonly(current_transaction, |txn| {
        let values = txn
            .json_path(&query)
            .map(|out| NifYOut::from_native(out, doc.clone()))
            .collect::<Vec<NifYOut>>();
        Ok(values)
    })?;

    Ok((atoms::ok(), values).encode(env))
}

#[rustler::nif]
fn doc_monitor_subdocs(
    doc: NifDoc,
    pid: LocalPid,
    metadata: Term<'_>,
) -> NifResult<(Atom, NifSubscription)> {
    let metadata = TermBox::new(metadata);
    let event_doc = doc.clone();
    doc.observe_subdocs(move |txn, event: &SubdocsEvent| {
        ENV.with(|env| {
            let active_subdoc_guids: HashSet<String> =
                txn.subdoc_guids().map(|guid| guid.to_string()).collect();
            let event = NifSubdocsEvent::new(event, &event_doc, &active_subdoc_guids);
            let metadata = metadata.get(*env);
            let _ = env.send(
                &pid,
                (
                    atoms::subdocs(),
                    event,
                    origin_to_term(env, txn.origin()),
                    metadata,
                ),
            );
        })
    })
    .map(|sub| {
        (
            atoms::ok(),
            NifSubscription {
                reference: ResourceArc::new(Mutex::new(Some(sub)).into()),
                doc: doc.clone(),
            },
        )
    })
    .map_err(|e| Error::from(e).into())
}

#[rustler::nif]
fn doc_client_id(doc: NifDoc) -> u64 {
    doc.client_id()
}

#[rustler::nif]
fn doc_guid(doc: NifDoc) -> String {
    doc.guid().to_string()
}

#[rustler::nif]
fn doc_collection_id(doc: NifDoc) -> String {
    doc.collection_id()
        .map(|id| id.to_string())
        .unwrap_or_default()
}

#[rustler::nif]
fn doc_skip_gc(doc: NifDoc) -> bool {
    doc.skip_gc()
}

#[rustler::nif]
fn doc_auto_load(doc: NifDoc) -> bool {
    doc.auto_load()
}

#[rustler::nif]
fn doc_should_load(doc: NifDoc) -> bool {
    doc.should_load()
}

#[rustler::nif]
fn doc_offset_kind(doc: NifDoc) -> NifOffsetKind {
    doc.offset_kind().into()
}
