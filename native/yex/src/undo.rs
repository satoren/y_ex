use crate::{
    shared_type::NifSharedType, utils::term_to_origin_binary, wrap::NifWrap,
    yinput::NifSharedTypeInput, NifDoc, NifError, ENV, atoms,
};

use rustler::{Env, LocalPid, ResourceArc, Term, Error as RustlerError, Encoder, NifResult, NifStruct};
use rustler::env::OwnedEnv;
use std::ops::Deref;
use std::sync::RwLock;
use yrs::{undo::Options as UndoOptions, UndoManager, Subscription};

pub struct UndoManagerWrapper {
    pub manager: UndoManager,
    pub item_added_observer: Option<(LocalPid, Subscription)>,
    pub item_updated_observer: Option<(LocalPid, Subscription)>,
    pub item_popped_observer: Option<(LocalPid, Subscription)>,
}

impl UndoManagerWrapper {
    pub fn new(manager: UndoManager) -> Self {
        Self { 
            manager, 
            item_added_observer: None, 
            item_updated_observer: None,
            item_popped_observer: None 
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

#[derive(NifStruct)]
#[module = "Yex.UndoManager"]
pub struct NifUndoManager {
    reference: ResourceArc<UndoManagerResource>,
}

#[rustler::nif]
pub fn undo_manager_new_with_options(
    env: Env<'_>,
    doc: NifDoc,
    scope: NifSharedTypeInput,
    options: NifUndoOptions,
) -> Result<NifUndoManager, NifError> {
    // Check if the document reference is valid by attempting to access its inner doc
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
    let branch = scope
        .readonly(None, |txn| scope.get_ref(txn))
        .map_err(|_| NifError::Message("Failed to get branch reference".to_string()))?;

    let undo_options = UndoOptions {
        capture_timeout_millis: options.capture_timeout,
        ..Default::default()
    };

    let undo_manager = UndoManager::with_scope_and_options(&doc, &branch, undo_options);
    let wrapper = UndoManagerWrapper::new(undo_manager);

    Ok(ResourceArc::new(NifWrap(RwLock::new(wrapper))))
}

#[rustler::nif]
pub fn undo_manager_include_origin(
    env: Env<'_>,
    undo_manager: NifUndoManager,
    origin_term: Term,
) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager
            .reference
            .0
            .write()
            .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;

        let origin = term_to_origin_binary(origin_term)
            .ok_or_else(|| NifError::Message("Invalid origin term".to_string()))?;
        wrapper.manager.include_origin(origin.as_slice());

        Ok(())
    })
}

#[rustler::nif]
pub fn undo_manager_exclude_origin(
    env: Env<'_>,
    undo_manager: NifUndoManager,
    origin_term: Term,
) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager
            .reference
            .0
            .write()
            .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;

        let origin = term_to_origin_binary(origin_term)
            .ok_or_else(|| NifError::Message("Invalid origin term".to_string()))?;
        wrapper.manager.exclude_origin(origin.as_slice());

        Ok(())
    })
}

#[rustler::nif]
pub fn undo_manager_undo(env: Env, undo_manager: NifUndoManager) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager
            .reference
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
pub fn undo_manager_redo(env: Env, undo_manager: NifUndoManager) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager
            .reference
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
    undo_manager: NifUndoManager,
    scope: NifSharedTypeInput,
) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager
            .reference
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
    undo_manager: NifUndoManager,
) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager
            .reference
            .0
            .write()
            .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;

        wrapper.manager.reset();
        Ok(())
    })
}

#[rustler::nif]
pub fn undo_manager_clear(env: Env, undo_manager: NifUndoManager) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager
            .reference
            .0
            .write()
            .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;

        wrapper.manager.clear();

        Ok(())
    })
}

#[rustler::nif]
pub fn undo_manager_observe_item_added(
    manager: NifUndoManager,
    observer: LocalPid
) -> NifResult<rustler::Atom> {
    let mut wrapper = manager
        .reference
        .0
        .write()
        .map_err(|_| RustlerError::Term(Box::new("Failed to acquire write lock")))?;
    
    if let Some((_pid, sub)) = wrapper.item_added_observer.take() {
        drop(sub);
    }

    let mut env = OwnedEnv::new();
    let observer = observer.clone();

    let subscription = wrapper.manager.observe_item_added(move |_txn, event| {
        let message = (
            atoms::item_added(),
            event.origin().map(|o| o.to_string()),
            atoms::text(),
            format!("{:?}", event)
        );

        env.send_and_clear(&observer, |env| message.encode(env));
    });

    wrapper.item_added_observer = Some((observer, subscription));
    Ok(atoms::ok())
}

#[rustler::nif]
pub fn undo_manager_observe_item_popped(
    manager: NifUndoManager,
    observer: LocalPid
) -> NifResult<rustler::Atom> {
    let mut wrapper = manager
        .reference
        .0
        .write()
        .map_err(|_| RustlerError::Term(Box::new("Failed to acquire write lock")))?;
    
    if let Some((_pid, sub)) = wrapper.item_popped_observer.take() {
        drop(sub);
    }

    let mut env = OwnedEnv::new();
    let observer = observer.clone();

    let subscription = wrapper.manager.observe_item_popped(move |_txn, event| {
        let message = (
            atoms::item_popped(),
            event.origin().map(|o| o.to_string()),
            atoms::text(),
            format!("{:?}", event)
        );

        env.send_and_clear(&observer, |env| message.encode(env));
    });

    wrapper.item_popped_observer = Some((observer, subscription));
    Ok(atoms::ok())
}

#[rustler::nif]
pub fn undo_manager_observe_item_updated(
    manager: NifUndoManager,
    observer: LocalPid
) -> NifResult<rustler::Atom> {
    let mut wrapper = manager
        .reference
        .0
        .write()
        .map_err(|_| RustlerError::Term(Box::new("Failed to acquire write lock")))?;
    
    if let Some((_pid, sub)) = wrapper.item_updated_observer.take() {
        drop(sub);
    }

    let mut env = OwnedEnv::new();
    let observer = observer.clone();

    let subscription = wrapper.manager.observe_item_updated(move |_txn, event| {
        let message = (
            atoms::item_updated(),
            event.origin().map(|o| o.to_string()),
            atoms::text(),
            format!("{:?}", event)
        );

        env.send_and_clear(&observer, |env| message.encode(env));
    });

    wrapper.item_updated_observer = Some((observer, subscription));
    Ok(atoms::ok())
}