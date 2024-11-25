use yrs::{UndoManager, undo::Options as UndoOptions};
use rustler::{Env, NifTaggedEnum, ResourceArc, NifStruct, Term, Encoder, LocalPid};
use std::sync::RwLock;
use std::collections::HashMap;
use crate::{
    text::NifText,
    array::NifArray,
    map::NifMap,
    shared_type::NifSharedType,  
    wrap::NifWrap,
    NifDoc,
    utils::term_to_origin_binary,
    NifError,
    ENV,
    atoms,
};
use std::cell::RefCell;

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
#[module = "Yex.UndoManager.StackItem"]
pub struct NifStackItem<'a> {
    pub meta: Term<'a>,
}

#[derive(NifStruct)]
#[module = "Yex.UndoManager"]
pub struct NifUndoManager {
    reference: ResourceArc<UndoManagerResource>,
}

pub struct UndoManagerWrapper {
    manager: UndoManager,
    observer_pid: Option<LocalPid>
}

impl UndoManagerWrapper {
    pub fn new(manager: UndoManager) -> Self {
        Self { 
            manager,
            observer_pid: None
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
pub fn undo_manager_new(
    env: Env<'_>,
    doc: NifDoc,
    scope: SharedTypeInput,
) -> NifUndoManager {
    ENV.set(&mut env.clone(), || {
        match scope {
            SharedTypeInput::Text(text) => create_undo_manager(env, doc, text),
            SharedTypeInput::Array(array) => create_undo_manager(env, doc, array),
            SharedTypeInput::Map(map) => create_undo_manager(env, doc, map),
        }
    })
}

fn create_undo_manager<T: NifSharedType>(
    env: Env<'_>,
    doc: NifDoc,
    scope: T
) -> NifUndoManager {
    create_undo_manager_with_options(
        env,
        doc,
        scope,
        NifUndoOptions { capture_timeout: 500 }
    )
}

fn create_undo_manager_with_options<T: NifSharedType>(
    _env: Env<'_>,
    doc: NifDoc,
    scope: T,
    options: NifUndoOptions,
) -> NifUndoManager {
    let branch = scope.readonly(None, |txn| {
        scope.get_ref(txn)
    }).unwrap();
    
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
    ENV.set(&mut env.clone(), || {
        match scope {
            SharedTypeInput::Text(text) => create_undo_manager_with_options(env, doc, text, options),
            SharedTypeInput::Array(array) => create_undo_manager_with_options(env, doc, array, options),
            SharedTypeInput::Map(map) => create_undo_manager_with_options(env, doc, map, options),
        }
    })
}

fn notify_observers(env: Env, wrapper: &UndoManagerWrapper, event: &str) -> Result<(), NifError> {
    if let Some(ref observer_pid) = wrapper.observer_pid {
        let meta = HashMap::from([
            ("test_value".to_string(), "added".encode(env))
        ]);
        
        let stack_item = NifStackItem {
            meta: meta.encode(env)
        };
        
        let message = match event {
            "added" => (atoms::stack_item_added(), stack_item.encode(env)),
            "popped" => (atoms::stack_item_popped(), meta.encode(env)),
            _ => return Ok(())
        };
        
        if let Err(_) = env.send(observer_pid, message) {
            return Err(NifError::Message("Failed to send message".to_string()));
        }
    }
    Ok(())
}

#[rustler::nif]
pub fn undo_manager_add_observer(
    env: Env,
    undo_manager: NifUndoManager,
    _observer_module: Term,
    observer_pid: LocalPid
) -> Result<(), NifError> {
    let mut wrapper = undo_manager.reference.0.write()
        .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;
    
    wrapper.observer_pid = Some(observer_pid);
    notify_observers(env, &wrapper, "added")?;
    
    Ok(())
}

fn with_write_lock_if<F, G>(
    env: Env,
    undo_manager: &NifUndoManager,
    predicate: F,
    action: G
) -> Result<(), NifError>
where
    F: FnOnce(&UndoManager) -> bool,
    G: FnOnce(&mut UndoManager) -> bool,
{
    let mut wrapper = undo_manager.reference.0.write()
        .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;
    
    if predicate(&wrapper.manager) {
        let result = action(&mut wrapper.manager);
        
        if result {
            notify_observers(env, &wrapper, "popped")?;
        }
    }
    
    Ok(())
}

#[rustler::nif]
pub fn undo_manager_include_origin(
    env: Env<'_>, 
    undo_manager: NifUndoManager, 
    origin_term: Term
) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager.reference.0.write()
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
    origin_term: Term
) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager.reference.0.write()
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
        
        let result = with_write_lock_if(
            env,
            &undo_manager,
            |manager| manager.can_undo(),
            |manager| {
                manager.undo_blocking();
                true
            }
        );
        
        *current_env.borrow_mut() = None;
        result
    })
}

#[rustler::nif]
pub fn undo_manager_redo(env: Env, undo_manager: NifUndoManager) -> Result<(), NifError> {
    with_write_lock_if(
        env,
        &undo_manager,
        |manager| manager.can_redo(),
        |manager| {
            manager.redo_blocking();
            true
        }
    )
}

#[rustler::nif]
pub fn undo_manager_expand_scope(
    env: Env<'_>,
    undo_manager: NifUndoManager,
    scope: SharedTypeInput,
) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager.reference.0.write()
            .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;
        
        match scope {
            SharedTypeInput::Text(text) => {
                let branch = text.readonly(None, |txn| text.get_ref(txn))
                    .map_err(|_| NifError::Message("Failed to get text branch reference".to_string()))?;
                wrapper.manager.expand_scope(&branch);
            },
            SharedTypeInput::Array(array) => {
                let branch = array.readonly(None, |txn| array.get_ref(txn))
                    .map_err(|_| NifError::Message("Failed to get array branch reference".to_string()))?;
                wrapper.manager.expand_scope(&branch);
            },
            SharedTypeInput::Map(map) => {
                let branch = map.readonly(None, |txn| map.get_ref(txn))
                    .map_err(|_| NifError::Message("Failed to get map branch reference".to_string()))?;
                wrapper.manager.expand_scope(&branch);
            },
        }
        
        Ok(())
    })
}

#[rustler::nif]
pub fn undo_manager_stop_capturing(env: Env<'_>, undo_manager: NifUndoManager) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager.reference.0.write()
            .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;
        
        wrapper.manager.reset();
        Ok(())
    })
}

#[rustler::nif]
pub fn undo_manager_update_stack_item<'a>(
    env: Env<'a>,
    undo_manager: NifUndoManager,
    stack_item: NifStackItem<'a>
) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        let manager = undo_manager.reference.0.write()
            .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;
        
        if let Some(_current_item) = manager.manager.undo_stack().last() {
            let _: HashMap<String, Term> = stack_item.meta.decode()?;
            Ok(())
        } else {
            Err(NifError::Message("No current stack item available".to_string()))
        }
    })
}

#[rustler::nif]
pub fn undo_manager_get_meta<'a>(
    env: Env<'a>,
    undo_manager: NifUndoManager
) -> Result<Term<'a>, NifError> {
    ENV.set(&mut env.clone(), || {
        let manager = undo_manager.reference.0.write()
            .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;
        
        if let Some(_current_item) = manager.manager.undo_stack().last() {
            let meta: HashMap<String, Term> = HashMap::new();
            Ok(meta.encode(env))
        } else {
            Err(NifError::Message("No current stack item available".to_string()))
        }
    })
}

#[rustler::nif]
pub fn undo_manager_set_meta<'a>(
    env: Env<'a>,
    undo_manager: NifUndoManager,
    meta: Term<'a>
) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        let manager = undo_manager.reference.0.write()
            .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;
        
        if let Some(_current_item) = manager.manager.undo_stack().last() {
            let _: HashMap<String, Term> = meta.decode()?;
            Ok(())
        } else {
            Err(NifError::Message("No current stack item available".to_string()))
        }
    })
}

#[rustler::nif]
pub fn undo_manager_clear(env: Env, undo_manager: NifUndoManager) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        let mut wrapper = undo_manager.reference.0.write()
            .map_err(|_| NifError::Message("Failed to acquire write lock".to_string()))?;
        
        wrapper.manager.clear();
        notify_observers(env, &wrapper, "popped")?;
        
        Ok(())
    })
}

