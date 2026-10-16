use std::{
    collections::{HashMap, HashSet},
    sync::Arc,
};

use rustler::{Encoder, Env, NifResult, NifStruct, NifUntaggedEnum, ResourceArc, Term};
use yrs::{
    types::{
        array::ArrayEvent,
        map::MapEvent,
        text::TextEvent,
        weak::WeakEvent,
        xml::{XmlEvent, XmlTextEvent},
        Change, Delta, EntryChange,
    },
    DeepObservable, Observable, SharedRef, TransactionMut,
};

use crate::{
    any::NifAny,
    array::NifArray,
    atoms,
    doc::NifDoc,
    map::NifMap,
    shared_type::NifSharedType,
    subscription::{NifSubscription, SubscriptionKey},
    term_box::TermBox,
    text::NifText,
    transaction::TransactionResource,
    utils::origin_to_term,
    weak::NifWeakLink,
    wrap::NifMapPairs,
    wrap::NifWrap,
    xml::NifXmlText,
    yinput::{with_shared_type, NifSharedTypeInput},
    youtput::NifYOut,
    ENV,
};

type NifPath = NifWrap<yrs::types::Path>;

impl rustler::Encoder for NifPath {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        let segments: Vec<Term> = self
            .0
            .iter()
            .map(|segment| match segment {
                yrs::types::PathSegment::Key(key) => key.encode(env),
                yrs::types::PathSegment::Index(index) => index.encode(env),
            })
            .collect();
        segments.encode(env)
    }
}

impl<'a> rustler::Decoder<'a> for NifPath {
    fn decode(term: Term<'a>) -> rustler::NifResult<Self> {
        let segments: Vec<Term> = term.decode()?;
        let path = segments
            .iter()
            .map(|segment| {
                if let Ok(key) = segment.decode::<&str>() {
                    Ok(yrs::types::PathSegment::Key(key.into()))
                } else if let Ok(index) = segment.decode::<u32>() {
                    Ok(yrs::types::PathSegment::Index(index))
                } else {
                    Err(rustler::Error::BadArg)
                }
            })
            .collect::<Result<Vec<yrs::types::PathSegment>, rustler::Error>>()?;
        Ok(NifWrap(yrs::types::Path::from(path)))
    }
}

pub struct NifYArrayChange {
    doc: NifDoc,
    change: Vec<yrs::types::Change>,
}

impl rustler::Encoder for NifYArrayChange {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        let v: Vec<Term<'_>> = self
            .change
            .iter()
            .map(|change| match change {
                Change::Added(content) => {
                    let content: Vec<Term<'_>> = content
                        .iter()
                        .cloned()
                        .map(|item| NifYOut::from_native(item, &self.doc).encode(env))
                        .collect();

                    let mut map = Term::map_new(env);
                    map = map.map_put(atoms::insert(), content).unwrap();
                    map
                }
                Change::Removed(index) => {
                    let mut map = Term::map_new(env);
                    map = map.map_put(atoms::delete(), *index).unwrap();
                    map
                }
                Change::Retain(index) => {
                    let mut map = Term::map_new(env);
                    map = map.map_put(atoms::retain(), *index).unwrap();
                    map
                }
            })
            .collect();
        v.encode(env)
    }
}

impl<'a> rustler::Decoder<'a> for NifYArrayChange {
    fn decode(_term: Term<'a>) -> rustler::NifResult<Self> {
        unimplemented!()
    }
}

pub trait NifEventConstructor<Event>
where
    Self: Sized + Encoder,
{
    fn new(doc: &NifDoc, event: &Event, txn: &TransactionMut<'_>) -> Self;
}

#[derive(NifStruct)]
#[module = "Yex.ArrayEvent"]
pub struct NifArrayEvent {
    pub path: NifPath,
    pub target: NifArray,
    pub change: NifYArrayChange,
}

impl NifEventConstructor<ArrayEvent> for NifArrayEvent {
    fn new(doc: &NifDoc, event: &ArrayEvent, txn: &TransactionMut<'_>) -> Self {
        NifArrayEvent {
            path: event.path().into(),
            target: NifArray::new(doc.clone(), event.target().clone()),
            change: NifYArrayChange {
                doc: doc.clone(),
                change: event.delta(txn).to_vec(),
            },
        }
    }
}

pub struct NifYTextDelta {
    doc: NifDoc,
    delta: Vec<yrs::types::Delta>,
}

impl rustler::Encoder for NifYTextDelta {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        let v: Vec<Term<'_>> = self
            .delta
            .iter()
            .map(|change| match change {
                Delta::Inserted(content, attr) => {
                    let insert = NifYOut::from_native(content.clone(), &self.doc);

                    let mut map = Term::map_new(env).map_put(atoms::insert(), insert).unwrap();
                    if let Some(attr) = attr {
                        let attribute = attr
                            .iter()
                            .map(|(k, v)| (k.to_string(), NifAny::from(v.clone())))
                            .collect::<NifMapPairs<NifAny>>();
                        map = map.map_put(atoms::attributes(), attribute).unwrap();
                    }
                    map
                }
                Delta::Deleted(index) => {
                    let mut map = Term::map_new(env);
                    map = map.map_put(atoms::delete(), *index).unwrap();
                    map
                }
                Delta::Retain(index, attr) => {
                    let mut map = Term::map_new(env);
                    map = map.map_put(atoms::retain(), *index).unwrap();
                    if let Some(attr) = attr {
                        let attribute = attr
                            .iter()
                            .map(|(k, v)| (k.to_string(), NifAny::from(v.clone())))
                            .collect::<NifMapPairs<NifAny>>();
                        map = map.map_put(atoms::attributes(), attribute).unwrap();
                    }
                    map
                }
            })
            .collect();
        v.encode(env)
    }
}

impl<'a> rustler::Decoder<'a> for NifYTextDelta {
    fn decode(_term: Term<'a>) -> rustler::NifResult<Self> {
        unimplemented!()
    }
}

#[derive(NifStruct)]
#[module = "Yex.TextEvent"]
pub struct NifTextEvent {
    pub path: NifPath,
    pub target: NifText,
    pub delta: NifYTextDelta,
}

impl NifEventConstructor<TextEvent> for NifTextEvent {
    fn new(doc: &NifDoc, event: &TextEvent, txn: &TransactionMut<'_>) -> Self {
        NifTextEvent {
            path: event.path().into(),
            target: NifText::new(doc.clone(), event.target().clone()),
            delta: NifYTextDelta {
                doc: doc.clone(),
                delta: event.delta(txn).to_vec(),
            },
        }
    }
}

pub struct NifYMapChange {
    doc: NifDoc,
    change: HashMap<Arc<str>, EntryChange>,
}

impl rustler::Encoder for NifYMapChange {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        let v: NifMapPairs<Term> = self
            .change
            .iter()
            .map(|(key, change)| match change {
                EntryChange::Inserted(content) => {
                    let content = NifYOut::from_native(content.clone(), &self.doc);
                    let map = Term::map_new(env)
                        .map_put(atoms::action(), atoms::add())
                        .unwrap()
                        .map_put(atoms::new_value(), content)
                        .unwrap();
                    (key.to_string(), map)
                }
                EntryChange::Removed(old_value) => {
                    let old_value = NifYOut::from_native(old_value.clone(), &self.doc);
                    let map = Term::map_new(env)
                        .map_put(atoms::action(), atoms::delete())
                        .unwrap()
                        .map_put(atoms::old_value(), old_value)
                        .unwrap();
                    (key.to_string(), map)
                }
                EntryChange::Updated(old_value, new_value) => {
                    let old_value = NifYOut::from_native(old_value.clone(), &self.doc);
                    let new_value = NifYOut::from_native(new_value.clone(), &self.doc);
                    let map = Term::map_new(env)
                        .map_put(atoms::action(), atoms::update())
                        .unwrap()
                        .map_put(atoms::old_value(), old_value)
                        .unwrap()
                        .map_put(atoms::new_value(), new_value)
                        .unwrap();
                    (key.to_string(), map)
                }
            })
            .collect();
        v.encode(env)
    }
}

impl<'a> rustler::Decoder<'a> for NifYMapChange {
    fn decode(_term: Term<'a>) -> rustler::NifResult<Self> {
        unimplemented!()
    }
}

#[derive(NifStruct)]
#[module = "Yex.MapEvent"]
pub struct NifMapEvent {
    pub path: NifPath,
    pub target: NifMap,
    pub keys: NifYMapChange,
}

impl NifEventConstructor<MapEvent> for NifMapEvent {
    fn new(doc: &NifDoc, event: &MapEvent, txn: &TransactionMut<'_>) -> Self {
        NifMapEvent {
            path: event.path().into(),
            target: NifMap::new(doc.clone(), event.target().clone()),
            keys: NifYMapChange {
                doc: doc.clone(),
                change: event.keys(txn).clone(),
            },
        }
    }
}

#[derive(NifStruct)]
#[module = "Yex.XmlEvent"]
pub struct NifXmlEvent {
    pub path: NifPath,
    pub target: NifYOut, // XmlFragment or XmlText or XmlElement

    pub delta: NifYArrayChange,

    pub keys: NifYMapChange,
}

impl NifEventConstructor<XmlEvent> for NifXmlEvent {
    fn new(doc: &NifDoc, event: &XmlEvent, txn: &TransactionMut<'_>) -> Self {
        NifXmlEvent {
            path: event.path().into(),
            target: NifYOut::from_xml_out(event.target().clone(), doc.clone()),
            keys: NifYMapChange {
                doc: doc.clone(),
                change: event.keys(txn).clone(),
            },
            delta: NifYArrayChange {
                doc: doc.clone(),
                change: event.delta(txn).to_vec(),
            },
        }
    }
}

#[derive(NifStruct)]
#[module = "Yex.XmlTextEvent"]
pub struct NifXmlTextEvent {
    pub path: NifPath,
    pub target: NifXmlText,
    pub delta: NifYTextDelta,
    pub keys: NifYMapChange,
}

impl NifEventConstructor<XmlTextEvent> for NifXmlTextEvent {
    fn new(doc: &NifDoc, event: &XmlTextEvent, txn: &TransactionMut<'_>) -> Self {
        NifXmlTextEvent {
            path: event.path().into(),
            target: NifXmlText::new(doc.clone(), event.target().clone()),
            delta: NifYTextDelta {
                doc: doc.clone(),
                delta: event.delta(txn).to_vec(),
            },
            keys: NifYMapChange {
                doc: doc.clone(),
                change: event.keys(txn).clone(),
            },
        }
    }
}

#[derive(NifStruct)]
#[module = "Yex.WeakLinkEvent"]
pub struct NifWeakLinkEvent {
    pub path: NifPath,
    pub target: NifWeakLink,
}

impl NifEventConstructor<WeakEvent> for NifWeakLinkEvent {
    fn new(doc: &NifDoc, event: &WeakEvent, _txn: &TransactionMut<'_>) -> Self {
        NifWeakLinkEvent {
            path: event.path().into(),
            target: NifWeakLink::new(doc.clone(), event.as_target()),
        }
    }
}

#[derive(NifUntaggedEnum)]
pub enum NifEvent {
    Text(NifTextEvent),
    Array(NifArrayEvent),
    Map(NifMapEvent),
    XmlFragment(NifXmlEvent),
    XmlText(NifXmlTextEvent),
    Weak(NifWeakLinkEvent),
}

impl NifEvent {
    pub fn new(doc: &NifDoc, event: &yrs::types::Event, txn: &TransactionMut<'_>) -> Self {
        match event {
            yrs::types::Event::Text(event) => NifEvent::Text(NifTextEvent::new(doc, event, txn)),
            yrs::types::Event::Array(event) => NifEvent::Array(NifArrayEvent::new(doc, event, txn)),
            yrs::types::Event::Map(event) => NifEvent::Map(NifMapEvent::new(doc, event, txn)),
            yrs::types::Event::XmlFragment(event) => {
                NifEvent::XmlFragment(NifXmlEvent::new(doc, event, txn))
            }
            yrs::types::Event::XmlText(event) => {
                NifEvent::XmlText(NifXmlTextEvent::new(doc, event, txn))
            }
            yrs::types::Event::Weak(event) => {
                NifEvent::Weak(NifWeakLinkEvent::new(doc, event, txn))
            }
        }
    }
}

pub trait NifSharedTypeDeepObservable
where
    Self: NifSharedType,
    Self::RefType: DeepObservable + Send + Sync + 'static,
{
    fn observe_deep(
        &self,
        current_transaction: Option<ResourceArc<TransactionResource>>,
        pid: rustler::LocalPid,
        ref_term: Term<'_>,
        metadata: Term<'_>,
    ) -> NifResult<NifSubscription> {
        let doc = self.doc();

        let ref_box = TermBox::new(ref_term);
        let metadata_box = TermBox::new(metadata);

        doc.readonly(current_transaction, |txn| {
            let ref_value = self.get_ref(txn)?;

            let (sub_key, state) = SubscriptionKey::new((pid, ref_box, metadata_box, doc.clone()));
            ref_value.observe_deep(sub_key.key.clone(), move |txn, events| {
                let Some(state) = state.get() else {
                    return;
                };
                let (pid, ref_box, metadata_box, doc_ref) = &*state;
                ENV.with(|env| {
                    let events: Vec<NifEvent> = events
                        .iter()
                        .map(|event| NifEvent::new(doc_ref, event, txn))
                        .collect();
                    let _ = env.send(
                        pid,
                        (
                            atoms::observe_deep_event(),
                            ref_box.get(*env),
                            events,
                            origin_to_term(env, txn.origin()),
                            metadata_box.get(*env),
                        ),
                    );
                })
            });

            let hook = ref_value.hook();
            let sub = sub_key.branch(doc.clone(), move |txn, key| {
                if let Some(shared) = hook.get(txn) {
                    shared.unobserve_deep(key.clone());
                }
            });
            Ok(NifSubscription::new(sub, doc.clone()))
        })
    }
}

pub trait NifSharedTypeObservable
where
    Self: NifSharedType,
    Self::RefType: Observable + Send + Sync + 'static,
    yrs::types::Event: AsRef<<Self::RefType as yrs::Observable>::Event>,
    Self::Event: NifEventConstructor<<<Self as NifSharedType>::RefType as Observable>::Event>,
{
    type Event;
    fn observe(
        &self,
        current_transaction: Option<ResourceArc<TransactionResource>>,
        pid: rustler::LocalPid,
        ref_term: Term<'_>,
        metadata: Term<'_>,
    ) -> NifResult<NifSubscription> {
        let doc = self.doc();

        let ref_box = TermBox::new(ref_term);
        let metadata_box = TermBox::new(metadata);

        doc.readonly(current_transaction, |txn| {
            let ref_value = self.get_ref(txn)?;

            let (sub_key, state) = SubscriptionKey::new((pid, ref_box, metadata_box, doc.clone()));
            ref_value.observe(sub_key.key.clone(), move |txn, event| {
                let Some(state) = state.get() else {
                    return;
                };
                let (pid, ref_box, metadata_box, doc_ref) = &*state;
                ENV.with(|env| {
                    let _ = env.send(
                        pid,
                        (
                            atoms::observe_event(),
                            ref_box.get(*env),
                            Self::Event::new(doc_ref, event, txn),
                            origin_to_term(env, txn.origin()),
                            metadata_box.get(*env),
                        ),
                    );
                })
            });

            let hook = ref_value.hook();
            let sub = sub_key.branch(doc.clone(), move |txn, key| {
                if let Some(shared) = hook.get(txn) {
                    shared.unobserve(key.clone());
                }
            });
            Ok(NifSubscription::new(sub, doc.clone()))
        })
    }
}

#[rustler::nif]
fn shared_type_observe(
    shared_type: NifSharedTypeInput,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    pid: rustler::LocalPid,
    ref_term: Term<'_>,
    metadata: Term<'_>,
) -> NifResult<NifSubscription> {
    with_shared_type!(shared_type, t => t.observe(current_transaction, pid, ref_term, metadata))
}

#[rustler::nif]
fn shared_type_observe_deep(
    shared_type: NifSharedTypeInput,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    pid: rustler::LocalPid,
    ref_term: Term<'_>,
    metadata: Term<'_>,
) -> NifResult<NifSubscription> {
    with_shared_type!(shared_type, t => t.observe_deep(current_transaction, pid, ref_term, metadata))
}

#[derive(NifStruct)]
#[module = "Yex.SubdocsEvent"]
pub struct NifSubdocsEvent {
    pub added: Vec<NifDoc>,
    pub removed: Vec<NifDoc>,
    pub loaded: Vec<NifDoc>,
}

impl NifSubdocsEvent {
    pub fn new(
        event: &yrs::SubdocsEvent,
        doc: &NifDoc,
        active_subdoc_guids: &HashSet<String>,
    ) -> Self {
        // `removed` first: when a doc is replaced by another with the same guid, the `added`
        // lookup replaces the cache entry, and the removed doc must still find its own.
        let removed = event
            .removed()
            .map(|subdoc| doc.with_subdoc_reference(subdoc.clone(), Some(active_subdoc_guids)))
            .collect();
        let added = event
            .added()
            .map(|subdoc| doc.with_cached_subdoc(subdoc.clone(), Some(active_subdoc_guids)))
            .collect();
        let loaded = event
            .loaded()
            .map(|subdoc| doc.with_cached_subdoc(subdoc.clone(), Some(active_subdoc_guids)))
            .collect();

        NifSubdocsEvent {
            added,
            removed,
            loaded,
        }
    }
}

#[derive(NifStruct)]
#[module = "Yex.TransactionCleanupEvent"]
pub struct NifTransactionCleanupEvent {
    pub before_state: HashMap<u64, u32>,
    pub after_state: HashMap<u64, u32>,
    pub delete_set: HashMap<u64, Vec<(u32, u32)>>,
}

impl From<&yrs::TransactionCleanupEvent> for NifTransactionCleanupEvent {
    /// Copies the state vectors and delete set into Elixir-encodable maps.
    fn from(event: &yrs::TransactionCleanupEvent) -> Self {
        NifTransactionCleanupEvent {
            before_state: state_vector_to_map(&event.before_state),
            after_state: state_vector_to_map(&event.after_state),
            delete_set: id_set_to_map(&event.delete_set),
        }
    }
}

/// `%{client_id => clock}`. yrs records a client that starts inserting in a transaction with
/// clock 0 in `before_state`; a zero clock means nothing was seen from that client, so it is
/// left out, as in yjs, where `beforeState` has no entry for such a client.
pub fn state_vector_to_map(sv: &yrs::StateVector) -> HashMap<u64, u32> {
    sv.iter()
        .filter(|(_, clock)| **clock > 0)
        .map(|(client, clock)| (client.get(), *clock))
        .collect()
}

/// `%{client_id => [{clock, len}]}`. yrs keeps each client's ranges sorted by clock and
/// merges adjacent ones on insert, so the lists come out ascending and squashed.
pub fn id_set_to_map(ids: &yrs::IdSet) -> HashMap<u64, Vec<(u32, u32)>> {
    ids.iter()
        .map(|(client, ranges)| {
            let ranges = ranges
                .iter()
                .map(|range| (range.start, range.end - range.start))
                .collect();
            (client.get(), ranges)
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::{id_set_to_map, state_vector_to_map};
    use std::collections::HashMap;
    use yrs::{ClientID, IdSet, StateVector, ID};

    #[test]
    fn state_vector_to_map_keys_by_client_and_drops_zero_clocks() {
        let sv: StateVector = [
            (ClientID::new(1), 5),
            (ClientID::new(7), 2),
            (ClientID::new(9), 0),
        ]
        .into_iter()
        .collect();
        assert_eq!(state_vector_to_map(&sv), HashMap::from([(1, 5), (7, 2)]));
        assert!(state_vector_to_map(&StateVector::default()).is_empty());
    }

    #[test]
    fn id_set_to_map_gives_ascending_squashed_clock_len_pairs() {
        let mut ids = IdSet::new();
        ids.insert(ID::new(ClientID::new(1), 10), 2);
        ids.insert(ID::new(ClientID::new(1), 0), 3);
        ids.insert(ID::new(ClientID::new(1), 3), 1);
        ids.insert(ID::new(ClientID::new(2), 4), 1);
        assert_eq!(
            id_set_to_map(&ids),
            HashMap::from([(1, vec![(0, 4), (10, 2)]), (2, vec![(4, 1)])])
        );
        assert!(id_set_to_map(&IdSet::new()).is_empty());
    }
}
