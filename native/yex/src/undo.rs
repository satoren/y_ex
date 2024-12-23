use crate::{
    atoms, shared_type::NifSharedType, utils::term_to_origin_binary, wrap::NifWrap,
    yinput::NifSharedTypeInput, NifDoc, NifError, ENV,
};

use rustler::{
    Atom, Encoder, Env, Error as RustlerError, LocalPid, NifResult, NifStruct, ResourceArc, Term,
};
use std::ops::Deref;
use std::sync::RwLock;
use uuid::Uuid;
use yrs::branch::BranchPtr;
use yrs::undo::UndoManager as YrsUndoManager;
use yrs::{undo::Options as UndoOptions, Subscription};

#[derive(Debug, Default, Clone)]
pub struct UndoMetadata {
    pub event_id: String,
}

#[derive(Debug, NifStruct)]
#[module = "Yex.UndoManager.Event"]
pub struct NifUndoEvent<'a> {
    pub meta: Term<'a>,
    pub origin: Option<Vec<u8>>,
    pub kind: Atom,
    pub changed_parent_types: Vec<String>,
}

pub struct UndoManagerWrapper {
    pub manager: YrsUndoManager<UndoMetadata>,
    pub item_added_observer: Option<(LocalPid, Subscription)>,
    pub item_updated_observer: Option<(LocalPid, Subscription)>,
    pub item_popped_observer: Option<(LocalPid, Subscription)>,
}

impl UndoManagerWrapper {
    pub fn new(manager: YrsUndoManager<UndoMetadata>) -> Self {
        Self {
            manager,
            item_added_observer: None,
            item_updated_observer: None,
            item_popped_observer: None,
        }
    }
}

pub type UndoManagerResource = NifWrap<RwLock<UndoManagerWrapper>>;

#[rustler::resource_impl]
impl rustler::Resource for UndoManagerResource {}

#[derive(NifStruct)]
#[module = "Yex.UndoManager.Options"]
pub struct NifUndoOptions {
    pub capture_timeout: u64,
}

#[rustler::nif]
pub fn undo_manager_new_with_options(
    env: Env<'_>,
    doc: NifDoc,
    scope: NifSharedTypeInput,
    options: NifUndoOptions,
) -> Result<ResourceArc<UndoManagerResource>, NifError> {
    // Check if the document reference is valid
    let _doc_ref = doc.reference.deref();

    match scope {
        NifSharedTypeInput::Text(text) => create_undo_manager_with_options(env, doc, text, options),
        NifSharedTypeInput::Array(array) => {
            create_undo_manager_with_options(env, doc, array, options)
        }
        NifSharedTypeInput::Map(map) => create_undo_manager_with_options(env, doc, map, options),
        NifSharedTypeInput::XmlText(text) => {
            create_undo_manager_with_options(env, doc, text, options)
        }
        NifSharedTypeInput::XmlElement(element) => {
            create_undo_manager_with_options(env, doc, element, options)
        }
        NifSharedTypeInput::XmlFragment(fragment) => {
            create_undo_manager_with_options(env, doc, fragment, options)
        }
    }
}

fn create_undo_manager_with_options<T: NifSharedType>(
    _env: Env<'_>,
    doc: NifDoc,
    scope: T,
    options: NifUndoOptions,
) -> Result<ResourceArc<UndoManagerResource>, NifError> {
    // Get branch reference using a read transaction
    let branch = scope
        .readonly(None, |txn| scope.get_ref(txn))
        .map_err(|_| NifError::Message("Failed to get branch reference".to_string()))?;

    let undo_options = UndoOptions {
        capture_timeout_millis: options.capture_timeout,
        ..Default::default()
    };

    let undo_manager =
        YrsUndoManager::<UndoMetadata>::with_scope_and_options(&doc, &branch, undo_options);
    let wrapper = UndoManagerWrapper::new(undo_manager);
    let resource = ResourceArc::new(NifWrap(RwLock::new(wrapper)));

    Ok(resource)
}

#[rustler::nif]
pub fn undo_manager_include_origin(
    env: Env<'_>,
    reference: ResourceArc<UndoManagerResource>,
    origin_term: Term,
) -> NifResult<Atom> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = reference
            .0
            .write()
            .map_err(|_| RustlerError::Term(Box::new("Failed to acquire write lock")))?;

        let origin = term_to_origin_binary(origin_term)
            .ok_or_else(|| RustlerError::Term(Box::new("Invalid origin term")))?;

        wrapper.manager.include_origin(origin.as_slice());
        Ok(atoms::ok())
    })
}

#[rustler::nif]
pub fn undo_manager_exclude_origin(
    env: Env<'_>,
    reference: ResourceArc<UndoManagerResource>,
    origin_term: Term,
) -> NifResult<Atom> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = reference
            .0
            .write()
            .map_err(|_| RustlerError::Term(Box::new("Failed to acquire write lock")))?;

        let origin = term_to_origin_binary(origin_term)
            .ok_or_else(|| RustlerError::Term(Box::new("Invalid origin term")))?;

        wrapper.manager.exclude_origin(origin.as_slice());
        Ok(atoms::ok())
    })
}

#[rustler::nif]
pub fn undo_manager_undo(
    env: Env,
    reference: ResourceArc<UndoManagerResource>,
) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = reference
            .0
            .write()
            .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;

        if wrapper.manager.can_undo() {
            wrapper.manager.undo_blocking();
        }

        Ok(())
    })
}

#[rustler::nif]
pub fn undo_manager_redo(
    env: Env,
    reference: ResourceArc<UndoManagerResource>,
) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = reference
            .0
            .write()
            .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;

        if wrapper.manager.can_redo() {
            wrapper.manager.redo_blocking();
        }

        Ok(())
    })
}

#[rustler::nif]
pub fn undo_manager_expand_scope(
    env: Env<'_>,
    reference: ResourceArc<UndoManagerResource>,
    scope: NifSharedTypeInput,
) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = reference
            .0
            .write()
            .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;

        match scope {
            NifSharedTypeInput::Text(text) => {
                let branch = text.readonly(None, |txn| text.get_ref(txn)).map_err(|_| {
                    NifError::Message("Failed to get text branch reference".to_string())
                })?;
                wrapper.manager.expand_scope(&branch);
            }
            NifSharedTypeInput::Array(array) => {
                let branch = array
                    .readonly(None, |txn| array.get_ref(txn))
                    .map_err(|_| {
                        NifError::Message("Failed to get array branch reference".to_string())
                    })?;
                wrapper.manager.expand_scope(&branch);
            }
            NifSharedTypeInput::Map(map) => {
                let branch = map.readonly(None, |txn| map.get_ref(txn)).map_err(|_| {
                    NifError::Message("Failed to get map branch reference".to_string())
                })?;
                wrapper.manager.expand_scope(&branch);
            }
            NifSharedTypeInput::XmlText(text) => {
                let branch = text.readonly(None, |txn| text.get_ref(txn)).map_err(|_| {
                    NifError::Message("Failed to get xml text branch reference".to_string())
                })?;
                wrapper.manager.expand_scope(&branch);
            }
            NifSharedTypeInput::XmlElement(element) => {
                let branch = element
                    .readonly(None, |txn| element.get_ref(txn))
                    .map_err(|_| {
                        NifError::Message("Failed to get xml element branch reference".to_string())
                    })?;
                wrapper.manager.expand_scope(&branch);
            }
            NifSharedTypeInput::XmlFragment(fragment) => {
                let branch = fragment
                    .readonly(None, |txn| fragment.get_ref(txn))
                    .map_err(|_| {
                        NifError::Message("Failed to get xml fragment branch reference".to_string())
                    })?;
                wrapper.manager.expand_scope(&branch);
            }
        }

        Ok(())
    })
}

#[rustler::nif]
pub fn undo_manager_stop_capturing(
    env: Env<'_>,
    reference: ResourceArc<UndoManagerResource>,
) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = reference
            .0
            .write()
            .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;

        wrapper.manager.reset();
        Ok(())
    })
}

#[rustler::nif]
pub fn undo_manager_clear(
    env: Env,
    reference: ResourceArc<UndoManagerResource>,
) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = reference
            .0
            .write()
            .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;

        wrapper.manager.clear();

        Ok(())
    })
}

// Helper function to map Yrs event kind to Elixir atom
fn map_event_kind(kind: yrs::undo::EventKind) -> Atom {
    match kind {
        yrs::undo::EventKind::Undo => atoms::undo(),
        yrs::undo::EventKind::Redo => atoms::redo(),
    }
}

// Helper function to convert BranchPtr slice to Vec<String>
fn map_parent_types(types: &[BranchPtr]) -> Vec<String> {
    types
        .iter()
        .map(|t| {
            let type_str = t.to_string();
            // Extract just the type name from the Y.js type string
            if type_str.starts_with("YText") {
                "text".to_string()
            } else if type_str.starts_with("YArray") {
                "array".to_string()
            } else if type_str.starts_with("YMap") {
                "map".to_string()
            } else if type_str.starts_with("YXmlText") {
                "xml_text".to_string()
            } else if type_str.starts_with("YXmlElement") {
                "xml_element".to_string()
            } else if type_str.starts_with("YXmlFragment") {
                "xml_fragment".to_string()
            } else {
                "unknown".to_string()
            }
        })
        .collect()
}

#[rustler::nif]
pub fn undo_manager_observe_item_added(
    reference: ResourceArc<UndoManagerResource>,
    observer: LocalPid,
) -> NifResult<rustler::Atom> {
    let mut wrapper = reference
        .0
        .write()
        .map_err(|_| RustlerError::Term(Box::new("Failed to acquire write lock")))?;

    if let Some((_pid, sub)) = wrapper.item_added_observer.take() {
        drop(sub);
    }

    let observer = observer.clone();

    let subscription = wrapper.manager.observe_item_added(move |_txn, event| {
        ENV.with(|env| {
            // Generate a new UUID for each event
            let event_id = Uuid::new_v4().to_string();

            // Update the event metadata
            *event.meta_mut() = UndoMetadata {
                event_id: event_id.clone(),
            };

            // Create metadata map with event_id
            let meta_map = rustler::types::map::map_new(*env);
            let meta_map = meta_map
                .map_put(atoms::event_id(), event_id.encode(*env))
                .expect("Failed to put event_id");

            let nif_event = NifUndoEvent {
                meta: meta_map,
                origin: event.origin().map(|o| o.as_ref().to_vec()),
                kind: map_event_kind(event.kind()),
                changed_parent_types: map_parent_types(event.changed_parent_types()),
            };

            let message = (atoms::item_added(), nif_event);
            let _ = env.send(&observer, message);
        });
    });

    wrapper.item_added_observer = Some((observer, subscription));
    Ok(atoms::ok())
}

#[rustler::nif]
pub fn undo_manager_observe_item_popped(
    reference: ResourceArc<UndoManagerResource>,
    observer: LocalPid,
) -> NifResult<rustler::Atom> {
    let mut wrapper = reference
        .0
        .write()
        .map_err(|_| RustlerError::Term(Box::new("Failed to acquire write lock")))?;

    if let Some((_pid, sub)) = wrapper.item_popped_observer.take() {
        drop(sub);
    }

    let observer = observer.clone();

    let subscription = wrapper.manager.observe_item_popped(move |_txn, event| {
        ENV.with(|env| {
            // Get the existing metadata with its ID
            let meta = event.meta();

            let map = rustler::types::map::map_new(*env)
                .map_put(atoms::event_id(), meta.event_id.encode(*env))
                .expect("Failed to put event_id");

            let nif_event = NifUndoEvent {
                meta: map,
                origin: event.origin().map(|o| o.as_ref().to_vec()),
                kind: map_event_kind(event.kind()),
                changed_parent_types: map_parent_types(event.changed_parent_types()),
            };

            // Use the same ID from the metadata
            let message = (atoms::item_popped(), meta.event_id.clone(), nif_event);

            let _ = env.send(&observer, message);
        });
    });

    wrapper.item_popped_observer = Some((observer, subscription));
    Ok(atoms::ok())
}

#[rustler::nif]
pub fn undo_manager_observe_item_updated(
    reference: ResourceArc<UndoManagerResource>,
    observer: LocalPid,
) -> NifResult<rustler::Atom> {
    let mut wrapper = reference
        .0
        .write()
        .map_err(|_| RustlerError::Term(Box::new("Failed to acquire write lock")))?;

    if let Some((_pid, sub)) = wrapper.item_updated_observer.take() {
        drop(sub);
    }

    let observer = observer.clone();

    let subscription = wrapper.manager.observe_item_updated(move |_txn, event| {
        ENV.with(|env| {
            let nif_event = NifUndoEvent {
                meta: event.meta().encode(*env),
                origin: event.origin().map(|o| o.as_ref().to_vec()),
                kind: map_event_kind(event.kind()),
                changed_parent_types: map_parent_types(event.changed_parent_types()),
            };

            let message = (atoms::item_updated(), nif_event);
            let _ = env.send(&observer, message);
        });
    });

    wrapper.item_updated_observer = Some((observer, subscription));
    Ok(atoms::ok())
}

#[rustler::nif]
pub fn undo_manager_can_undo(reference: ResourceArc<UndoManagerResource>) -> NifResult<bool> {
    let wrapper = reference
        .0
        .read()
        .map_err(|_| RustlerError::Term(Box::new("Failed to acquire read lock")))?;

    Ok(wrapper.manager.can_undo())
}

#[rustler::nif]
pub fn undo_manager_unobserve_item_added(
    reference: ResourceArc<UndoManagerResource>,
) -> NifResult<rustler::Atom> {
    let mut wrapper = reference
        .0
        .write()
        .map_err(|_| RustlerError::Term(Box::new("Failed to acquire write lock")))?;

    if let Some((_pid, sub)) = wrapper.item_added_observer.take() {
        drop(sub);
    }

    Ok(atoms::ok())
}

// Implement Drop to ensure cleanup
impl Drop for UndoManagerWrapper {
    fn drop(&mut self) {
        // Remove all observers first
        if let Some((_pid, sub)) = self.item_added_observer.take() {
            drop(sub);
        }
        if let Some((_pid, sub)) = self.item_updated_observer.take() {
            drop(sub);
        }
        if let Some((_pid, sub)) = self.item_popped_observer.take() {
            drop(sub);
        }
        // Clear the manager
        self.manager.clear();
    }
}

// Implement Encoder for UndoMetadata
impl rustler::Encoder for UndoMetadata {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        let map = rustler::types::map::map_new(env);
        map.map_put(atoms::event_id(), self.event_id.encode(env))
            .expect("Failed to put event_id")
    }
}
