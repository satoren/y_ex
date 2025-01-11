use crate::{
    shared_type::NifSharedType, utils::term_to_origin_binary, wrap::NifWrap,
    yinput::NifSharedTypeInput, Error, NifDoc, ENV,
};

use rustler::{Env, NifStruct, ResourceArc, Term};
use std::ops::Deref;
use std::sync::RwLock;
use yrs::{undo::Options as UndoOptions, UndoManager};

#[derive(NifStruct)]
#[module = "Yex.UndoManager"]
pub struct NifUndoManager {
    reference: ResourceArc<UndoManagerResource>,
    doc: NifDoc,
}

pub struct UndoManagerWrapper {
    manager: UndoManager,
}

impl UndoManagerWrapper {
    pub fn new(manager: UndoManager) -> Self {
        Self { manager }
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
pub fn undo_manager_new(
    env: Env<'_>,
    doc: NifDoc,
    scope: NifSharedTypeInput,
) -> Result<NifUndoManager, Error> {
    ENV.set(&mut env.clone(), || match scope {
        NifSharedTypeInput::Text(text) => create_undo_manager(env, doc, text),
        NifSharedTypeInput::Array(array) => create_undo_manager(env, doc, array),
        NifSharedTypeInput::Map(map) => create_undo_manager(env, doc, map),
        NifSharedTypeInput::XmlText(text) => create_undo_manager(env, doc, text),
        NifSharedTypeInput::XmlElement(element) => create_undo_manager(env, doc, element),
        NifSharedTypeInput::XmlFragment(fragment) => create_undo_manager(env, doc, fragment),
    })
}

fn create_undo_manager<T: NifSharedType>(
    env: Env<'_>,
    doc: NifDoc,
    scope: T,
) -> Result<NifUndoManager, Error> {
    create_undo_manager_with_options(
        env,
        doc,
        scope,
        NifUndoOptions {
            capture_timeout: 500,
        },
    )
}

fn create_undo_manager_with_options<T: NifSharedType>(
    _env: Env<'_>,
    doc: NifDoc,
    scope: T,
    options: NifUndoOptions,
) -> Result<NifUndoManager, Error> {
    let branch = scope
        .readonly(None, |txn| scope.get_ref(txn))
        .map_err(|_| Error::Message("Failed to get branch reference".to_string()))?;

    let undo_options = UndoOptions {
        capture_timeout_millis: options.capture_timeout,
        ..Default::default()
    };

    let undo_manager = UndoManager::with_scope_and_options(&doc, &branch, undo_options);
    let wrapper = UndoManagerWrapper::new(undo_manager);

    Ok(NifUndoManager {
        reference: ResourceArc::new(NifWrap(RwLock::new(wrapper))),
        doc: doc,
    })
}

#[rustler::nif]
pub fn undo_manager_new_with_options(
    env: Env<'_>,
    doc: NifDoc,
    scope: NifSharedTypeInput,
    options: NifUndoOptions,
) -> Result<NifUndoManager, Error> {
    // Check if the document reference is valid by attempting to access its inner doc
    // will return an error tuple if it is not
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

#[rustler::nif]
pub fn undo_manager_include_origin(
    env: Env<'_>,
    undo_manager: NifUndoManager,
    origin_term: Term,
) -> Result<(), Error> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager
            .reference
            .0
            .write()
            .map_err(|_| Error::Message("Failed to acquire write lock".to_string()))?;

        let origin = term_to_origin_binary(origin_term)
            .ok_or_else(|| Error::Message("Invalid origin term".to_string()))?;
        wrapper.manager.include_origin(origin.as_slice());

        Ok(())
    })
}

#[rustler::nif]
pub fn undo_manager_exclude_origin(
    env: Env<'_>,
    undo_manager: NifUndoManager,
    origin_term: Term,
) -> Result<(), Error> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager
            .reference
            .0
            .write()
            .map_err(|_| Error::Message("Failed to acquire write lock".to_string()))?;

        let origin = term_to_origin_binary(origin_term)
            .ok_or_else(|| Error::Message("Invalid origin term".to_string()))?;
        wrapper.manager.exclude_origin(origin.as_slice());

        Ok(())
    })
}

#[rustler::nif]
pub fn undo_manager_undo(env: Env, undo_manager: NifUndoManager) -> Result<(), Error> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager
            .reference
            .0
            .write()
            .map_err(|_| Error::Message("Failed to acquire write lock".to_string()))?;

        if wrapper.manager.can_undo() {
            wrapper.manager.undo_blocking();
        }

        Ok(())
    })
}

#[rustler::nif]
pub fn undo_manager_redo(env: Env, undo_manager: NifUndoManager) -> Result<(), Error> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager
            .reference
            .0
            .write()
            .map_err(|_| Error::Message("Failed to acquire write lock".to_string()))?;

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
) -> Result<(), Error> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager
            .reference
            .0
            .write()
            .map_err(|_| Error::Message("Failed to acquire write lock".to_string()))?;

        match scope {
            NifSharedTypeInput::Text(text) => {
                let branch = text.readonly(None, |txn| text.get_ref(txn)).map_err(|_| {
                    Error::Message("Failed to get text branch reference".to_string())
                })?;
                wrapper.manager.expand_scope(&branch);
            }
            NifSharedTypeInput::Array(array) => {
                let branch = array
                    .readonly(None, |txn| array.get_ref(txn))
                    .map_err(|_| {
                        Error::Message("Failed to get array branch reference".to_string())
                    })?;
                wrapper.manager.expand_scope(&branch);
            }
            NifSharedTypeInput::Map(map) => {
                let branch = map.readonly(None, |txn| map.get_ref(txn)).map_err(|_| {
                    Error::Message("Failed to get map branch reference".to_string())
                })?;
                wrapper.manager.expand_scope(&branch);
            }
            NifSharedTypeInput::XmlText(text) => {
                let branch = text.readonly(None, |txn| text.get_ref(txn)).map_err(|_| {
                    Error::Message("Failed to get xml text branch reference".to_string())
                })?;
                wrapper.manager.expand_scope(&branch);
            }
            NifSharedTypeInput::XmlElement(element) => {
                let branch = element
                    .readonly(None, |txn| element.get_ref(txn))
                    .map_err(|_| {
                        Error::Message("Failed to get xml element branch reference".to_string())
                    })?;
                wrapper.manager.expand_scope(&branch);
            }
            NifSharedTypeInput::XmlFragment(fragment) => {
                let branch = fragment
                    .readonly(None, |txn| fragment.get_ref(txn))
                    .map_err(|_| {
                        Error::Message("Failed to get xml fragment branch reference".to_string())
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
) -> Result<(), Error> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager
            .reference
            .0
            .write()
            .map_err(|_| Error::Message("Failed to acquire write lock".to_string()))?;

        wrapper.manager.reset();
        Ok(())
    })
}

#[rustler::nif]
pub fn undo_manager_clear(env: Env, undo_manager: NifUndoManager) -> Result<(), Error> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager
            .reference
            .0
            .write()
            .map_err(|_| Error::Message("Failed to acquire write lock".to_string()))?;

        wrapper.manager.clear();

        Ok(())
    })
}
