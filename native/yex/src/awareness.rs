use std::{collections::HashMap, sync::Mutex};

use crate::error::Error;
use crate::subscription::NifSubscription;
use crate::term_box::TermBox;
use crate::utils::{origin_to_term, term_to_origin_binary};
use crate::{
    atoms,
    wrap::{NifWrap, SliceIntoBinary},
    NifAny, NifDoc, ENV,
};
use rustler::{
    Atom, Binary, Encoder, Env, LocalPid, NifMap, NifResult, NifStruct, ResourceArc, Term,
};
use yrs::{
    block::ClientID,
    sync::{Awareness, AwarenessUpdate},
    updates::{decoder::Decode, encoder::Encode},
};

pub type AwarenessResource = NifWrap<Awareness>;
#[rustler::resource_impl]
impl rustler::Resource for AwarenessResource {}

#[derive(NifStruct)]
#[module = "Yex.Awareness"]
pub struct NifAwareness {
    reference: ResourceArc<AwarenessResource>,
    doc: NifDoc,
}

#[derive(NifMap)]
pub struct NifAwarenessUpdateSummary {
    /// New clients added as part of the update.
    pub added: Vec<ClientID>,
    /// Existing clients that have been changed by the update.
    pub updated: Vec<ClientID>,
    /// Existing clients that have been removed by the update.
    pub removed: Vec<ClientID>,
}

#[rustler::nif]
fn awareness_new(doc: NifDoc) -> NifAwareness {
    let awareness = Awareness::new(doc.reference.0.clone());
    let resource = AwarenessResource::from(awareness);
    NifAwareness {
        reference: ResourceArc::new(resource),
        doc: doc,
    }
}

#[rustler::nif]
fn awareness_client_id(awareness: NifAwareness) -> u64 {
    awareness.reference.client_id()
}
#[rustler::nif]
fn awareness_get_client_ids(awareness: NifAwareness) -> Vec<ClientID> {
    awareness
        .reference
        .iter()
        .filter_map(|(id, state)| {
            if let Some(_) = state.data {
                Some(id)
            } else {
                None
            }
        })
        .collect()
}
#[rustler::nif]
fn awareness_get_states(awareness: NifAwareness) -> HashMap<ClientID, NifAny> {
    awareness
        .reference
        .iter()
        .filter_map(|(id, state)| {
            if let Some(data) = state.data {
                match serde_json::from_str::<yrs::Any>(&data) {
                    Ok(any) => Some((id, any.into())),
                    Err(_) => None,
                }
            } else {
                None
            }
        })
        .collect()
}

#[rustler::nif]
fn awareness_get_local_state(awareness: NifAwareness) -> Option<NifAny> {
    awareness
        .reference
        .local_state()
        .map(|a: yrs::Any| a.into())
}
#[rustler::nif]
fn awareness_set_local_state(
    env: Env<'_>,
    awareness: NifAwareness,
    json: NifAny,
) -> NifResult<Atom> {
    ENV.set(&mut env.clone(), || {
        awareness
            .reference
            .set_local_state(json.0)
            .map(|_| atoms::ok())
            .map_err(|e| Error::from(e).into())
    })
}

#[rustler::nif]
fn awareness_clean_local_state(env: Env<'_>, awareness: NifAwareness) -> NifResult<Atom> {
    ENV.set(&mut env.clone(), || {
        awareness.reference.clean_local_state();
        Ok(atoms::ok())
    })
}

#[rustler::nif]
fn awareness_monitor_update(
    awareness: NifAwareness,
    pid: LocalPid,
    metadata: Term<'_>,
) -> NifSubscription {
    let metadata = TermBox::new(metadata);
    let sub = awareness
        .reference
        .on_update(move |_awareness, event, origin| {
            let summary = event.summary();

            let summary = NifAwarenessUpdateSummary {
                added: summary.added.clone(),
                updated: summary.updated.clone(),
                removed: summary.removed.clone(),
            };
            ENV.with(|env| {
                let metadata = metadata.get(*env);
                let _ = env.send(
                    &pid,
                    (
                        atoms::awareness_update(),
                        summary,
                        origin_to_term(env, origin),
                        metadata,
                    ),
                );
            })
        });
    NifSubscription {
        reference: ResourceArc::new(Mutex::new(Some(sub)).into()),
        doc: awareness.doc.clone(),
    }
}

#[rustler::nif]
fn awareness_monitor_change(
    awareness: NifAwareness,
    pid: LocalPid,
    metadata: Term<'_>,
) -> NifSubscription {
    let metadata = TermBox::new(metadata);
    let sub = awareness
        .reference
        .on_change(move |_awareness, event, origin| {
            let summary = event.summary();

            let summary = NifAwarenessUpdateSummary {
                added: summary.added.clone(),
                updated: summary.updated.clone(),
                removed: summary.removed.clone(),
            };
            ENV.with(|env| {
                let metadata = metadata.get(*env);
                let _ = env.send(
                    &pid,
                    (
                        atoms::awareness_change(),
                        summary,
                        origin_to_term(env, origin),
                        metadata,
                    ),
                );
            })
        });
    NifSubscription {
        reference: ResourceArc::new(Mutex::new(Some(sub)).into()),
        doc: awareness.doc.clone(),
    }
}

#[rustler::nif]
pub fn awareness_encode_update_v1(
    env: Env<'_>,
    awareness: NifAwareness,
    clients: Option<Vec<ClientID>>,
) -> NifResult<Term<'_>> {
    let update = if let Some(clients) = clients {
        awareness
            .reference
            .update_with_clients(clients)
            .map_err(Error::from)?
    } else {
        awareness.reference.update().map_err(Error::from)?
    };

    Ok((
        atoms::ok(),
        SliceIntoBinary::new(update.encode_v1().as_slice()),
    )
        .encode(env))
}
#[rustler::nif]
pub fn awareness_apply_update_v1(
    env: Env<'_>,
    awareness: NifAwareness,
    update: Binary,
    origin: Term<'_>,
) -> NifResult<Atom> {
    ENV.set(&mut env.clone(), || {
        let update = AwarenessUpdate::decode_v1(update.as_slice()).map_err(Error::from)?;

        if let Some(origin) = term_to_origin_binary(origin) {
            awareness
                .reference
                .apply_update_with(update, origin.as_slice())
                .map(|_| atoms::ok())
                .map_err(|e| Error::from(e).into())
        } else {
            awareness
                .reference
                .apply_update(update)
                .map(|_| atoms::ok())
                .map_err(|e| Error::from(e).into())
        }
    })
}
#[rustler::nif]
pub fn awareness_remove_states(
    env: Env<'_>,
    awareness: NifAwareness,
    clients: Vec<ClientID>,
) -> () {
    ENV.set(&mut env.clone(), || {
        for client_id in clients {
            awareness.reference.remove_state(client_id);
        }
    })
}
