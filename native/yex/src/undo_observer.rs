use rustler::{LocalPid, NifResult, NifStruct, ResourceArc, Error as RustlerError, Encoder};
use rustler::env::OwnedEnv;
use rustler::thread::ThreadSpawner;
use rustler::JobSpawner;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc;
use super::undo::UndoManagerResource;
use crate::atoms;

static NEXT_EVENT_ID: AtomicU64 = AtomicU64::new(1);

pub fn generate_event_id() -> u64 {
    NEXT_EVENT_ID.fetch_add(1, Ordering::SeqCst)
}

#[derive(NifStruct)]
#[module = "Yex.UndoObserver.Event"]
pub struct NifUndoEvent {
    pub id: u64,
    pub origin: Option<String>,
    pub changed_types: Vec<String>,
}

#[rustler::nif]
pub fn undo_manager_observe_item_added(
    manager: ResourceArc<UndoManagerResource>,
    observer: LocalPid
) -> NifResult<()> {
    let mut wrapper = manager.0.write()
        .map_err(|_| RustlerError::Term(Box::new("Failed to acquire write lock")))?;
    
    let (sender, receiver) = mpsc::channel();
    let thread_observer = observer.clone();
    
    // Create a thread to handle sending messages to Elixir
    ThreadSpawner::spawn(move || {
        let mut owned_env = OwnedEnv::new();
        while let Ok(nif_event) = receiver.recv() {
            owned_env.send_and_clear(&thread_observer, |env| {
                (atoms::item_added(), nif_event).encode(env)
            }).unwrap();
        }
    });

    // Register the callback with yrs
    let subscription = wrapper.manager.observe_item_added(move |_txn, event| {
        let event_id = generate_event_id();
        let nif_event = NifUndoEvent {
            id: event_id,
            origin: event.origin().map(|o| o.to_string()),
            changed_types: Vec::new(),
        };
        let _ = sender.send(nif_event);
    });

    wrapper.item_added_observer = Some((observer, subscription));
    Ok(())
}

#[rustler::nif]
pub fn undo_manager_observe_item_popped(
    manager: ResourceArc<UndoManagerResource>,
    observer: LocalPid
) -> NifResult<()> {
    let mut wrapper = manager.0.write()
        .map_err(|_| RustlerError::Term(Box::new("Failed to acquire write lock")))?;
    
    let (sender, receiver) = mpsc::channel();
    let thread_observer = observer.clone();
    
    // Create a thread to handle sending messages to Elixir
    ThreadSpawner::spawn(move || {
        let mut owned_env = OwnedEnv::new();
        while let Ok((id, nif_event)) = receiver.recv() {
            owned_env.send_and_clear(&thread_observer, |env| {
                (atoms::item_popped(), id, nif_event).encode(env)
            }).unwrap();
        }
    });

    // Register the callback with yrs
    let subscription = wrapper.manager.observe_item_popped(move |_txn, event| {
        let event_id = generate_event_id();
        let nif_event = NifUndoEvent {
            id: event_id,
            origin: event.origin().map(|o| o.to_string()),
            changed_types: Vec::new(),
        };
        let _ = sender.send((event_id, nif_event));
    });

    wrapper.item_popped_observer = Some((observer, subscription));
    Ok(())
}
  