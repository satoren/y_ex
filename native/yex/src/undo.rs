use crate::{
    array::NifArray, map::NifMap, shared_type::NifSharedType, text::NifText,
    utils::term_to_origin_binary, wrap::NifWrap, NifDoc, NifError, ENV,
};
use rustler::{Env, NifStruct, NifTaggedEnum, ResourceArc, Term};
use std::cell::RefCell;
use std::sync::RwLock;
use yrs::{undo::Options as UndoOptions, UndoManager};

thread_local! {
    static CURRENT_ENV: RefCell<Option<Env<'static>>> = RefCell::new(None);
}

#[derive(NifTaggedEnum)]
pub enum SharedTypeInput {
    Text(NifText),
    Array(NifArray),
    Map(NifMap),
}

#[derive(NifStruct)]
#[module = "Yex.UndoManager"]
pub struct NifUndoManager {
    reference: ResourceArc<UndoManagerResource>,
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
pub fn undo_manager_new(env: Env<'_>, doc: NifDoc, scope: SharedTypeInput) -> NifUndoManager {
    ENV.set(&mut env.clone(), || match scope {
        SharedTypeInput::Text(text) => create_undo_manager(env, doc, text),
        SharedTypeInput::Array(array) => create_undo_manager(env, doc, array),
        SharedTypeInput::Map(map) => create_undo_manager(env, doc, map),
    })
}

fn create_undo_manager<T: NifSharedType>(env: Env<'_>, doc: NifDoc, scope: T) -> NifUndoManager {
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
) -> NifUndoManager {
    let branch = scope.readonly(None, |txn| scope.get_ref(txn)).unwrap();

    let undo_options = UndoOptions {
        capture_timeout_millis: options.capture_timeout,
        ..Default::default()
    };

    let undo_manager = UndoManager::with_scope_and_options(&doc, &branch, undo_options);
    let wrapper = UndoManagerWrapper::new(undo_manager);

    NifUndoManager {
        reference: ResourceArc::new(NifWrap(RwLock::new(wrapper))),
    }
}

#[rustler::nif]
pub fn undo_manager_new_with_options(
    env: Env<'_>,
    doc: NifDoc,
    scope: SharedTypeInput,
    options: NifUndoOptions,
) -> NifUndoManager {
    ENV.set(&mut env.clone(), || match scope {
        SharedTypeInput::Text(text) => create_undo_manager_with_options(env, doc, text, options),
        SharedTypeInput::Array(array) => create_undo_manager_with_options(env, doc, array, options),
        SharedTypeInput::Map(map) => create_undo_manager_with_options(env, doc, map, options),
    })
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

        if let Some(origin) = term_to_origin_binary(origin_term) {
            wrapper.manager.include_origin(origin.as_slice());
        }

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

        if let Some(origin) = term_to_origin_binary(origin_term) {
            wrapper.manager.exclude_origin(origin.as_slice());
        }

        Ok(())
    })
}

#[rustler::nif]
pub fn undo_manager_undo(env: Env, undo_manager: NifUndoManager) -> Result<(), NifError> {
    CURRENT_ENV.with(|current_env| {
        *current_env.borrow_mut() = Some(unsafe { std::mem::transmute(env) });

        let result = ENV.set(&mut env.clone(), || {
            let mut wrapper = undo_manager
                .reference
                .0
                .write()
                .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;

            if wrapper.manager.can_undo() {
                wrapper.manager.undo_blocking();
            }

            Ok(())
        });

        *current_env.borrow_mut() = None;
        result
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
    scope: SharedTypeInput,
) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager
            .reference
            .0
            .write()
            .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;

        match scope {
            SharedTypeInput::Text(text) => {
                let branch = text.readonly(None, |txn| text.get_ref(txn)).map_err(|_| {
                    NifError::Message("Failed to get text branch reference".to_string())
                })?;
                wrapper.manager.expand_scope(&branch);
            }
            SharedTypeInput::Array(array) => {
                let branch = array
                    .readonly(None, |txn| array.get_ref(txn))
                    .map_err(|_| {
                        NifError::Message("Failed to get array branch reference".to_string())
                    })?;
                wrapper.manager.expand_scope(&branch);
            }
            SharedTypeInput::Map(map) => {
                let branch = map.readonly(None, |txn| map.get_ref(txn)).map_err(|_| {
                    NifError::Message("Failed to get map branch reference".to_string())
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
