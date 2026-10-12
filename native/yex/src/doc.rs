use std::collections::{HashMap, HashSet};
// Standard library imports
use std::ops::Deref;
use std::sync::{Mutex, RwLock};

// External crates
use rustler::{
    Atom, Binary, Decoder, Encoder, Env, LocalPid, NifResult, NifStruct, NifUnitEnum, ResourceArc,
    Term,
};
use yrs::encoding::read::Read as _;
use yrs::updates::{
    decoder::{Decode, DecoderV1},
    encoder::{Encode, Encoder as UpdatesEncoder, EncoderV1, EncoderV2},
};
use yrs::*;

use crate::event::NifSubdocsEvent;
// Internal imports
use crate::{
    atoms,
    decode::{catch_decode_v2, decode_update_v2},
    deferred::Deferred,
    error::Error,
    subscription::{DocEvent, NifSubscription, SubscriptionKey},
    term_box::TermBox,
    transaction::{take_then_drop, ReadTransaction, TransactionResource},
    utils::{client_id, origin_to_term, term_to_origin_binary},
    wrap::SliceIntoBinary,
    xml::NifXmlFragment,
    youtput::NifYOut,
    NifArray, NifMap, NifText, ENV,
};

pub(crate) struct DocResource {
    pub(crate) doc: Doc,
    pub(crate) subdocs: Mutex<HashMap<String, ResourceArc<DocResource>>>,
    pub(crate) deferred: Deferred,
}

impl DocResource {
    pub(crate) fn new(doc: Doc) -> Self {
        DocResource {
            doc,
            subdocs: Mutex::new(HashMap::new()),
            deferred: Deferred::default(),
        }
    }
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
    /// Default value: randomly generated (`None`).
    pub client_id: Option<u64>,
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

impl TryFrom<NifOptions> for Options {
    type Error = rustler::Error;

    fn try_from(w: NifOptions) -> NifResult<Options> {
        let offset_kind = match w.offset_kind {
            NifOffsetKind::Bytes => OffsetKind::Bytes,
            NifOffsetKind::Utf16 => OffsetKind::Utf16,
        };
        let guid = if let Some(id) = w.guid {
            id.into()
        } else {
            uuid_v4()
        };
        Ok(Options {
            client_id: match w.client_id {
                Some(id) => client_id(id)?,
                None => ClientID::random(),
            },
            guid,
            collection_id: w.collection_id.map(|s| s.into()),
            offset_kind,
            skip_gc: w.skip_gc,
            auto_load: w.auto_load,
            should_load: w.should_load,
            cleanup_formatting: true,
        })
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
            reference: ResourceArc::new(DocResource::new(Doc::new())),
            worker_pid: None,
        }
    }
}
impl NifDoc {
    pub fn with_options(option: NifOptions) -> NifResult<Self> {
        Ok(NifDoc {
            reference: ResourceArc::new(DocResource::new(Doc::with_options(option.try_into()?))),
            worker_pid: None,
        })
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

            // A guid can outlive the doc it was cached for: a destroyed subdoc is replaced in
            // its parent by a new Doc with the same guid, and a map entry can be replaced by
            // another doc with that guid, so only reuse the cached resource when it still wraps
            // the same Doc.
            // Note: two live subdocs sharing a guid evict each other's entry; each lookup
            // is still correct, but the resource reference returned is not stable.
            if let Some(reference) = cache.get(&subdoc_guid) {
                if Doc::ptr_eq(&reference.doc, &subdoc) {
                    return reference.clone();
                }
            }

            let reference: ResourceArc<DocResource> = ResourceArc::new(DocResource::new(subdoc));
            if cache_on_miss {
                cache.insert(subdoc_guid, reference.clone());
            }
            reference
        } else {
            ResourceArc::new(DocResource::new(subdoc))
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
                        Some(txn) => {
                            self.reference.deferred.run_unobserves(txn);
                            f(txn)
                        }
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
        let result = {
            let txn = yrs::Transact::try_transact(&self.reference.doc).map_err(Error::from)?;
            f(&txn)
        };
        self.reference.deferred.release_undo_managers();
        result
    }

    fn with_transaction_mut<F, T>(&self, f: F) -> NifResult<T>
    where
        F: FnOnce(&mut TransactionMut) -> NifResult<T>,
    {
        let result = {
            let mut txn =
                yrs::Transact::try_transact_mut(&self.reference.doc).map_err(Error::from)?;
            self.reference.deferred.run_unobserves(&txn);
            f(&mut txn)
        };
        self.reference.deferred.release_undo_managers();
        result
    }
}

#[rustler::nif]
fn doc_new() -> NifDoc {
    NifDoc::default()
}

#[rustler::nif]
fn doc_with_options(option: NifOptions) -> NifResult<NifDoc> {
    NifDoc::with_options(option)
}

#[rustler::nif]
fn doc_get_or_insert_text(
    env: Env<'_>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    name: &str,
) -> NifResult<NifText> {
    doc.mutably(env, current_transaction, |txn| {
        Ok(NifText::new(doc.clone(), txn.get_or_insert_text(name)))
    })
}

#[rustler::nif]
fn doc_get_or_insert_array(
    env: Env<'_>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    name: &str,
) -> NifResult<NifArray> {
    doc.mutably(env, current_transaction, |txn| {
        Ok(NifArray::new(doc.clone(), txn.get_or_insert_array(name)))
    })
}

#[rustler::nif]
fn doc_get_or_insert_map(
    env: Env<'_>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    name: &str,
) -> NifResult<NifMap> {
    doc.mutably(env, current_transaction, |txn| {
        Ok(NifMap::new(doc.clone(), txn.get_or_insert_map(name)))
    })
}

#[rustler::nif]
fn doc_get_or_insert_xml_fragment(
    env: Env<'_>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    name: &str,
) -> NifResult<NifXmlFragment> {
    doc.mutably(env, current_transaction, |txn| {
        Ok(NifXmlFragment::new(
            doc.clone(),
            txn.get_or_insert_xml_fragment(name),
        ))
    })
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
        doc.reference.deferred.run_unobserves(&txn);
        let txn: TransactionMut<'static> = unsafe { std::mem::transmute(txn) };

        Ok(TransactionResource(RwLock::new(Some(txn)), doc.reference.clone()).into())
    } else {
        let txn: TransactionMut =
            yrs::Transact::try_transact_mut(&doc.reference.doc).map_err(Error::from)?;
        doc.reference.deferred.run_unobserves(&txn);
        let txn: TransactionMut<'static> = unsafe { std::mem::transmute(txn) };
        Ok(TransactionResource(RwLock::new(Some(txn)), doc.reference.clone()).into())
    }
}

#[rustler::nif]
fn commit_transaction(env: Env<'_>, current_transaction: ResourceArc<TransactionResource>) {
    ENV.set(&mut env.clone(), || {
        take_then_drop(&current_transaction.0);
        current_transaction.1.deferred.release_undo_managers();
    })
}

#[rustler::nif]
fn doc_monitor_update_v1(
    doc: NifDoc,
    pid: LocalPid,
    metadata: Term<'_>,
) -> NifResult<(Atom, NifSubscription)> {
    let (sub_key, state) = SubscriptionKey::new((pid, TermBox::new(metadata)));

    doc.observe_update_v1(sub_key.key.clone(), move |txn, event| {
        let Some(state) = state.get() else {
            return;
        };
        let (pid, metadata) = &*state;
        ENV.with(|env| {
            let metadata = metadata.get(*env);
            let _ = env.send(
                pid,
                (
                    atoms::update_v1(),
                    SliceIntoBinary::new(event.update.as_slice()),
                    origin_to_term(env, txn.origin()),
                    metadata,
                ),
            );
        })
    })
    .map(|_| {
        (
            atoms::ok(),
            NifSubscription::new(sub_key.doc(doc.clone(), DocEvent::UpdateV1), doc.clone()),
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
    let (sub_key, state) = SubscriptionKey::new((pid, TermBox::new(metadata)));

    doc.observe_update_v2(sub_key.key.clone(), move |txn, event| {
        let Some(state) = state.get() else {
            return;
        };
        let (pid, metadata) = &*state;
        ENV.with(|env| {
            let metadata = metadata.get(*env);
            let _ = env.send(
                pid,
                (
                    atoms::update_v2(),
                    SliceIntoBinary::new(event.update.as_slice()),
                    origin_to_term(env, txn.origin()),
                    metadata,
                ),
            );
        })
    })
    .map(|_| {
        (
            atoms::ok(),
            NifSubscription::new(sub_key.doc(doc.clone(), DocEvent::UpdateV2), doc.clone()),
        )
    })
    .map_err(|e| Error::from(e).into())
}

fn apply_update_v1_impl(
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
fn apply_update_v1(
    env: Env<'_>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    update: Binary,
) -> NifResult<Atom> {
    apply_update_v1_impl(env, doc, current_transaction, update)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn apply_update_v1_dirty(
    env: Env<'_>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    update: Binary,
) -> NifResult<Atom> {
    apply_update_v1_impl(env, doc, current_transaction, update)
}

fn apply_update_v2_impl(
    env: Env<'_>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    update: Binary,
) -> NifResult<Atom> {
    let update = decode_update_v2(update.as_slice())?;

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
    apply_update_v2_impl(env, doc, current_transaction, update)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn apply_update_v2_dirty(
    env: Env<'_>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    update: Binary,
) -> NifResult<Atom> {
    apply_update_v2_impl(env, doc, current_transaction, update)
}

fn merge_updates_v1_impl<'a>(env: Env<'a>, updates: Vec<Binary<'a>>) -> NifResult<Term<'a>> {
    let merged =
        yrs::merge_updates_v1(updates.iter().map(Binary::as_slice)).map_err(Error::from)?;
    Ok((atoms::ok(), SliceIntoBinary::new(merged.as_slice())).encode(env))
}

#[rustler::nif]
fn merge_updates_v1<'a>(env: Env<'a>, updates: Vec<Binary<'a>>) -> NifResult<Term<'a>> {
    merge_updates_v1_impl(env, updates)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn merge_updates_v1_dirty<'a>(env: Env<'a>, updates: Vec<Binary<'a>>) -> NifResult<Term<'a>> {
    merge_updates_v1_impl(env, updates)
}

fn merge_updates_v2_impl<'a>(env: Env<'a>, updates: Vec<Binary<'a>>) -> NifResult<Term<'a>> {
    // Only the decode is caught: a panic while merging decodable updates stays a
    // :nif_panicked raise, as with merge_updates_v1.
    let updates = updates
        .iter()
        .map(|update| decode_update_v2(update.as_slice()))
        .collect::<Result<Vec<_>, _>>()?;
    let merged = Update::merge_updates(updates).encode_v2();
    Ok((atoms::ok(), SliceIntoBinary::new(merged.as_slice())).encode(env))
}

#[rustler::nif]
fn merge_updates_v2<'a>(env: Env<'a>, updates: Vec<Binary<'a>>) -> NifResult<Term<'a>> {
    merge_updates_v2_impl(env, updates)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn merge_updates_v2_dirty<'a>(env: Env<'a>, updates: Vec<Binary<'a>>) -> NifResult<Term<'a>> {
    merge_updates_v2_impl(env, updates)
}

#[rustler::nif]
fn update_debug_v1<'a>(env: Env<'a>, update: Binary<'a>) -> NifResult<Term<'a>> {
    let update = Update::decode_v1(update.as_slice()).map_err(Error::from)?;
    Ok((atoms::ok(), format!("{:#?}", update)).encode(env))
}

#[rustler::nif]
fn update_debug_v2<'a>(env: Env<'a>, update: Binary<'a>) -> NifResult<Term<'a>> {
    let update = decode_update_v2(update.as_slice())?;
    Ok((atoms::ok(), format!("{:#?}", update)).encode(env))
}

/// Decodes a v1 update and rejects input left unread. A v2 payload starts with a zero
/// byte, which the v1 decoder reads as an empty update before stopping, so the leftover
/// bytes are what tell a v2 update passed by mistake from a real empty one.
fn decode_update_v1(update: &[u8]) -> Result<Update, Error> {
    decode_v1_exact(update, "update")
}

/// Decodes a v1 state vector and rejects input left unread. The yrs v2 framing of a
/// state vector (`encode_state_vector_v2/1`) starts with a zero byte too, which the v1
/// decoder would otherwise read as the empty state vector.
fn decode_state_vector_v1(state_vector: &[u8]) -> Result<StateVector, Error> {
    decode_v1_exact(state_vector, "state vector")
}

fn decode_v1_exact<T: Decode>(bytes: &[u8], what: &str) -> Result<T, Error> {
    let mut decoder = DecoderV1::from(bytes);
    let decoded = T::decode(&mut decoder)?;
    if decoder.read_u8().is_ok() {
        return Err(Error::Encoding(yrs::encoding::read::Error::Custom(
            format!("{what} has trailing bytes"),
        )));
    }
    Ok(decoded)
}

fn ok_binary(env: Env<'_>, bytes: Vec<u8>) -> NifResult<Term<'_>> {
    Ok((atoms::ok(), SliceIntoBinary::new(bytes.as_slice())).encode(env))
}

fn diff_update_v1_impl<'a>(
    env: Env<'a>,
    update: Binary<'a>,
    state_vector: Binary<'a>,
) -> NifResult<Term<'a>> {
    // yrs diff_updates_v1 decodes both inputs without a leftover-byte check, so a v2
    // update or state vector would come back as an empty or meaningless diff. Update has
    // no public diff method, so the inputs are validated here and decoded again by yrs.
    decode_state_vector_v1(state_vector.as_slice())?;
    decode_update_v1(update.as_slice())?;
    let diff =
        yrs::diff_updates_v1(update.as_slice(), state_vector.as_slice()).map_err(Error::from)?;
    ok_binary(env, diff)
}

#[rustler::nif]
fn diff_update_v1<'a>(
    env: Env<'a>,
    update: Binary<'a>,
    state_vector: Binary<'a>,
) -> NifResult<Term<'a>> {
    diff_update_v1_impl(env, update, state_vector)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn diff_update_v1_dirty<'a>(
    env: Env<'a>,
    update: Binary<'a>,
    state_vector: Binary<'a>,
) -> NifResult<Term<'a>> {
    diff_update_v1_impl(env, update, state_vector)
}

fn diff_update_v2_impl<'a>(
    env: Env<'a>,
    update: Binary<'a>,
    state_vector: Binary<'a>,
) -> NifResult<Term<'a>> {
    // yjs reads the state vector in v1 encoding for both update formats. yrs
    // diff_updates_v2 expects the yrs v2 framing and Update::encode_diff is not public,
    // so the (small) state vector is re-framed.
    let state_vector = decode_state_vector_v1(state_vector.as_slice())?.encode_v2();
    let diff = catch_decode_v2(|| yrs::diff_updates_v2(update.as_slice(), &state_vector))?;
    ok_binary(env, diff)
}

#[rustler::nif]
fn diff_update_v2<'a>(
    env: Env<'a>,
    update: Binary<'a>,
    state_vector: Binary<'a>,
) -> NifResult<Term<'a>> {
    diff_update_v2_impl(env, update, state_vector)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn diff_update_v2_dirty<'a>(
    env: Env<'a>,
    update: Binary<'a>,
    state_vector: Binary<'a>,
) -> NifResult<Term<'a>> {
    diff_update_v2_impl(env, update, state_vector)
}

fn encode_state_vector_from_update_v1_impl<'a>(
    env: Env<'a>,
    update: Binary<'a>,
) -> NifResult<Term<'a>> {
    let update = decode_update_v1(update.as_slice())?;
    ok_binary(env, update.state_vector().encode_v1())
}

#[rustler::nif]
fn encode_state_vector_from_update_v1<'a>(env: Env<'a>, update: Binary<'a>) -> NifResult<Term<'a>> {
    encode_state_vector_from_update_v1_impl(env, update)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn encode_state_vector_from_update_v1_dirty<'a>(
    env: Env<'a>,
    update: Binary<'a>,
) -> NifResult<Term<'a>> {
    encode_state_vector_from_update_v1_impl(env, update)
}

fn encode_state_vector_from_update_v2_impl<'a>(
    env: Env<'a>,
    update: Binary<'a>,
) -> NifResult<Term<'a>> {
    // yjs has one state vector wire format for both update formats: the v1 one.
    let update = decode_update_v2(update.as_slice())?;
    ok_binary(env, update.state_vector().encode_v1())
}

#[rustler::nif]
fn encode_state_vector_from_update_v2<'a>(env: Env<'a>, update: Binary<'a>) -> NifResult<Term<'a>> {
    encode_state_vector_from_update_v2_impl(env, update)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn encode_state_vector_from_update_v2_dirty<'a>(
    env: Env<'a>,
    update: Binary<'a>,
) -> NifResult<Term<'a>> {
    encode_state_vector_from_update_v2_impl(env, update)
}

fn convert_update_format_v1_to_v2_impl<'a>(
    env: Env<'a>,
    update: Binary<'a>,
) -> NifResult<Term<'a>> {
    ok_binary(env, decode_update_v1(update.as_slice())?.encode_v2())
}

#[rustler::nif]
fn convert_update_format_v1_to_v2<'a>(env: Env<'a>, update: Binary<'a>) -> NifResult<Term<'a>> {
    convert_update_format_v1_to_v2_impl(env, update)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn convert_update_format_v1_to_v2_dirty<'a>(
    env: Env<'a>,
    update: Binary<'a>,
) -> NifResult<Term<'a>> {
    convert_update_format_v1_to_v2_impl(env, update)
}

fn convert_update_format_v2_to_v1_impl<'a>(
    env: Env<'a>,
    update: Binary<'a>,
) -> NifResult<Term<'a>> {
    let update = decode_update_v2(update.as_slice())?;
    ok_binary(env, update.encode_v1())
}

#[rustler::nif]
fn convert_update_format_v2_to_v1<'a>(env: Env<'a>, update: Binary<'a>) -> NifResult<Term<'a>> {
    convert_update_format_v2_to_v1_impl(env, update)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn convert_update_format_v2_to_v1_dirty<'a>(
    env: Env<'a>,
    update: Binary<'a>,
) -> NifResult<Term<'a>> {
    convert_update_format_v2_to_v1_impl(env, update)
}

#[derive(rustler::NifMap)]
struct NifUpdateMeta {
    from: HashMap<u64, u32>,
    to: HashMap<u64, u32>,
}

/// yjs parseUpdateMeta: per client, the clock of the first struct and the end of the
/// last one. Skips are left out; yjs and yrs only emit them between structs, never as a
/// client's first or last one, so the result matches yjs. The delete set is not read.
fn update_meta(update: &Update) -> NifUpdateMeta {
    let from = update
        .state_vector_lower()
        .iter()
        .map(|(client, clock)| (client.get(), *clock))
        .collect();
    let to = update
        .insertions(true)
        .iter()
        .filter_map(|(client, ranges)| {
            ranges
                .iter()
                .map(|range| range.end)
                .max()
                .map(|end| (client.get(), end))
        })
        .collect();
    NifUpdateMeta { from, to }
}

fn parse_update_meta_v1_impl(update: Binary) -> NifResult<(Atom, NifUpdateMeta)> {
    let update = decode_update_v1(update.as_slice())?;
    Ok((atoms::ok(), update_meta(&update)))
}

#[rustler::nif]
fn parse_update_meta_v1(update: Binary) -> NifResult<(Atom, NifUpdateMeta)> {
    parse_update_meta_v1_impl(update)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn parse_update_meta_v1_dirty(update: Binary) -> NifResult<(Atom, NifUpdateMeta)> {
    parse_update_meta_v1_impl(update)
}

fn parse_update_meta_v2_impl(update: Binary) -> NifResult<(Atom, NifUpdateMeta)> {
    let update = decode_update_v2(update.as_slice())?;
    Ok((atoms::ok(), update_meta(&update)))
}

#[rustler::nif]
fn parse_update_meta_v2(update: Binary) -> NifResult<(Atom, NifUpdateMeta)> {
    parse_update_meta_v2_impl(update)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn parse_update_meta_v2_dirty(update: Binary) -> NifResult<(Atom, NifUpdateMeta)> {
    parse_update_meta_v2_impl(update)
}

fn decode_state_vector_impl(state_vector: Binary) -> NifResult<(Atom, HashMap<u64, u32>)> {
    let state_vector = decode_state_vector_v1(state_vector.as_slice())?;
    let clocks = state_vector
        .iter()
        .map(|(client, clock)| (client.get(), *clock))
        .collect();
    Ok((atoms::ok(), clocks))
}

#[rustler::nif]
fn decode_state_vector(state_vector: Binary) -> NifResult<(Atom, HashMap<u64, u32>)> {
    decode_state_vector_impl(state_vector)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn decode_state_vector_dirty(state_vector: Binary) -> NifResult<(Atom, HashMap<u64, u32>)> {
    decode_state_vector_impl(state_vector)
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

fn encode_state_as_update_v1_impl<'a>(
    env: Env<'a>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    state_vector: Option<Binary>,
    item_limit: Option<u64>,
) -> NifResult<Term<'a>> {
    let sv = if let Some(vector) = state_vector {
        StateVector::decode_v1(vector.as_slice()).map_err(Error::from)?
    } else {
        StateVector::default()
    };

    doc.readonly(current_transaction, |txn| {
        if txn.exceeds_item_limit(item_limit) {
            return Ok(atoms::dirty().encode(env));
        }
        let vec = txn.encode_diff_v1(&sv);
        Ok((atoms::ok(), SliceIntoBinary::new(vec.as_slice())).encode(env))
    })
}

/// Returns `:dirty` without encoding when the doc holds more than `item_limit` items.
#[rustler::nif]
fn encode_state_as_update_v1<'a>(
    env: Env<'a>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    state_vector: Option<Binary>,
    item_limit: Option<u64>,
) -> NifResult<Term<'a>> {
    encode_state_as_update_v1_impl(env, doc, current_transaction, state_vector, item_limit)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn encode_state_as_update_v1_dirty<'a>(
    env: Env<'a>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    state_vector: Option<Binary>,
) -> NifResult<Term<'a>> {
    encode_state_as_update_v1_impl(env, doc, current_transaction, state_vector, None)
}

fn encode_diff_and_state_vector_v1_impl<'a>(
    env: Env<'a>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    remote_state_vector: Binary<'a>,
    item_limit: Option<u64>,
) -> NifResult<Term<'a>> {
    let sv = StateVector::decode_v1(remote_state_vector.as_slice()).map_err(Error::from)?;
    doc.readonly(current_transaction, |txn| {
        if txn.exceeds_item_limit(item_limit) {
            return Ok(atoms::dirty().encode(env));
        }
        let diff = txn.encode_diff_v1(&sv);
        let local_sv = txn.state_vector().encode_v1();
        Ok((
            atoms::ok(),
            SliceIntoBinary::new(diff.as_slice()),
            SliceIntoBinary::new(local_sv.as_slice()),
        )
            .encode(env))
    })
}

/// Single read transaction for sync step1 response: missing diff vs remote SV + local encoded SV.
/// Returns `:dirty` without encoding when the doc holds more than `item_limit` items.
#[rustler::nif]
fn encode_diff_and_state_vector_v1<'a>(
    env: Env<'a>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    remote_state_vector: Binary<'a>,
    item_limit: Option<u64>,
) -> NifResult<Term<'a>> {
    encode_diff_and_state_vector_v1_impl(
        env,
        doc,
        current_transaction,
        remote_state_vector,
        item_limit,
    )
}

#[rustler::nif(schedule = "DirtyCpu")]
fn encode_diff_and_state_vector_v1_dirty<'a>(
    env: Env<'a>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    remote_state_vector: Binary<'a>,
) -> NifResult<Term<'a>> {
    encode_diff_and_state_vector_v1_impl(env, doc, current_transaction, remote_state_vector, None)
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
fn encode_state_as_update_v2_impl<'a>(
    env: Env<'a>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    state_vector: Option<Binary>,
    item_limit: Option<u64>,
) -> NifResult<Term<'a>> {
    let sv = if let Some(vector) = state_vector {
        catch_decode_v2(|| StateVector::decode_v2(vector.as_slice()))?
    } else {
        StateVector::default()
    };

    doc.readonly(current_transaction, |txn| {
        if txn.exceeds_item_limit(item_limit) {
            return Ok(atoms::dirty().encode(env));
        }
        let vec = txn.encode_diff_v2(&sv);
        Ok((atoms::ok(), SliceIntoBinary::new(vec.as_slice())).encode(env))
    })
}

/// Returns `:dirty` without encoding when the doc holds more than `item_limit` items.
#[rustler::nif]
fn encode_state_as_update_v2<'a>(
    env: Env<'a>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    state_vector: Option<Binary>,
    item_limit: Option<u64>,
) -> NifResult<Term<'a>> {
    encode_state_as_update_v2_impl(env, doc, current_transaction, state_vector, item_limit)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn encode_state_as_update_v2_dirty<'a>(
    env: Env<'a>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    state_vector: Option<Binary>,
) -> NifResult<Term<'a>> {
    encode_state_as_update_v2_impl(env, doc, current_transaction, state_vector, None)
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
fn prune_pending_v1<'a>(
    env: Env<'a>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<Term<'a>> {
    doc.mutably(env, current_transaction, |txn| {
        let result = txn.prune_pending().map(|update| {
            let bytes = update.encode_v1();
            SliceIntoBinary::new(bytes.as_slice()).encode(env)
        });
        Ok((atoms::ok(), result).encode(env))
    })
}

// GC walks every block in the document, so keep it off the normal schedulers.
#[rustler::nif(schedule = "DirtyCpu")]
fn doc_force_gc(
    env: Env<'_>,
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<Atom> {
    doc.mutably(env, current_transaction, |txn| {
        txn.gc(None);
        Ok(atoms::ok())
    })
}

/// Returns the parent of a subdocument, failing instead of blocking when the document is
/// locked by an open transaction.
fn try_parent_doc(doc: &NifDoc) -> NifResult<Option<Doc>> {
    let txn = yrs::Transact::try_transact(&doc.reference.doc).map_err(Error::from)?;
    Ok(txn.parent_doc())
}

#[rustler::nif]
fn doc_load(env: Env<'_>, doc: NifDoc) -> NifResult<Atom> {
    ENV.set(&mut env.clone(), || {
        match try_parent_doc(&doc)? {
            Some(parent) => {
                // Committing the parent transaction emits the `loaded` subdocs event.
                let mut parent_txn =
                    yrs::Transact::try_transact_mut(&parent).map_err(Error::from)?;
                doc.reference.doc.load(&mut parent_txn);
            }
            None => {
                // A root document has no parent to notify. Doc::load still needs a write
                // transaction, so a throwaway one only serves to set `should_load`.
                let scratch = Doc::new();
                let mut scratch_txn = yrs::Transact::transact_mut(&scratch);
                doc.reference.doc.load(&mut scratch_txn);
            }
        }
        Ok(atoms::ok())
    })
}

#[rustler::nif]
fn doc_destroy(env: Env<'_>, doc: NifDoc) -> NifResult<Atom> {
    ENV.set(&mut env.clone(), || {
        let parent = try_parent_doc(&doc)?;
        // Doc::destroy blocks on the document lock, so fail first if it is held.
        drop(yrs::Transact::try_transact_mut(&doc.reference.doc).map_err(Error::from)?);
        match parent {
            Some(parent) => {
                // Committing the parent transaction emits the `removed`/`added` subdocs event.
                let mut parent_txn =
                    yrs::Transact::try_transact_mut(&parent).map_err(Error::from)?;
                doc.reference.doc.destroy(Some(&mut parent_txn));
            }
            None => doc.reference.doc.destroy(None),
        }
        Ok(atoms::ok())
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
            .map(|out| NifYOut::from_native(out, &doc))
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
    let (sub_key, state) = SubscriptionKey::new((pid, TermBox::new(metadata), doc.clone()));

    doc.observe_subdocs(sub_key.key.clone(), move |txn, event: &SubdocsEvent| {
        let Some(state) = state.get() else {
            return;
        };
        let (pid, metadata, event_doc) = &*state;
        ENV.with(|env| {
            let active_subdoc_guids: HashSet<String> =
                txn.subdoc_guids().map(|guid| guid.to_string()).collect();
            let event = NifSubdocsEvent::new(event, event_doc, &active_subdoc_guids);
            let metadata = metadata.get(*env);
            let _ = env.send(
                pid,
                (
                    atoms::subdocs(),
                    event,
                    origin_to_term(env, txn.origin()),
                    metadata,
                ),
            );
        })
    })
    .map(|_| {
        (
            atoms::ok(),
            NifSubscription::new(sub_key.doc(doc.clone(), DocEvent::Subdocs), doc.clone()),
        )
    })
    .map_err(|e| Error::from(e).into())
}

#[rustler::nif]
fn doc_client_id(doc: NifDoc) -> u64 {
    doc.client_id().get()
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
