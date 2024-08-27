use std::{collections::HashMap, sync::Mutex};

use crate::{
    atoms,
    subscription::SubscriptionResource,
    wrap::{encode_binary_slice_to_term, NifWrap},
    NifAny, NifDoc, NifError, ENV,
};
use rustler::{Binary, Encoder, Env, LocalPid, NifMap, NifStruct, ResourceArc, Term};
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
fn awareness_new<'a>(env: Env<'a>, doc: NifDoc) -> Result<Term<'a>, NifError> {
    let awareness = Awareness::new(doc.clone());
    let resource = AwarenessResource::from(awareness);
    let nif_awareness = NifAwareness {
        reference: ResourceArc::new(resource),
    };
    Ok(nif_awareness.encode(env))
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
) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        awareness
            .reference
            .set_local_state(json.0)
            .map_err(|e| NifError {
                reason: atoms::error(),
                message: e.to_string(),
            })
    })
}

#[rustler::nif]
fn awareness_clean_local_state(env: Env<'_>, awareness: NifAwareness) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        awareness.reference.clean_local_state();
        Ok(())
    })
}

#[rustler::nif]
fn awareness_monitor_update(
    env: Env<'_>,
    awareness: NifAwareness,
    pid: LocalPid,
) -> ResourceArc<SubscriptionResource> {
    ENV.set(&mut env.clone(), || {
        let awareness_ref = awareness.reference.clone();
        let sub = awareness
            .reference
            .on_update(move |_awareness, event, origin| {
                let summary = event.summary();

                let summary = NifAwarenessUpdateSummary {
                    added: summary.added.clone(),
                    updated: summary.updated.clone(),
                    removed: summary.removed.clone(),
                };
                let origin = origin.map(|origin| (*origin).to_string());
                let awareness_ref = awareness_ref.clone();
                ENV.with(|env| {
                    let _ = env.send(
                        &pid,
                        (
                            atoms::awareness_update(),
                            summary,
                            origin,
                            NifAwareness {
                                reference: awareness_ref,
                            },
                        ),
                    );
                })
            });
        ResourceArc::new(Mutex::new(Some(sub)).into())
    })
}

#[rustler::nif]
fn awareness_monitor_change(
    env: Env<'_>,
    awareness: NifAwareness,
    pid: LocalPid,
) -> ResourceArc<SubscriptionResource> {
    ENV.set(&mut env.clone(), || {
        let awareness_ref = awareness.reference.clone();
        let sub = awareness
            .reference
            .on_change(move |_awareness, event, origin| {
                let summary = event.summary();

                let summary = NifAwarenessUpdateSummary {
                    added: summary.added.clone(),
                    updated: summary.updated.clone(),
                    removed: summary.removed.clone(),
                };
                let origin = origin.map(|origin| origin.clone()).map(|o| o.to_string());
                let awareness_ref = awareness_ref.clone();
                ENV.with(|env| {
                    let _ = env.send(
                        &pid,
                        (
                            atoms::awareness_change(),
                            summary,
                            origin,
                            NifAwareness {
                                reference: awareness_ref,
                            },
                        ),
                    );
                })
            });
        ResourceArc::new(Mutex::new(Some(sub)).into())
    })
}

#[rustler::nif]
pub fn awareness_encode_update_v1(
    env: Env<'_>,
    awareness: NifAwareness,
    clients: Option<Vec<ClientID>>,
) -> Result<Term<'_>, NifError> {
    let update = if let Some(clients) = clients {
        awareness
            .reference
            .update_with_clients(clients)
            .map_err(|e| NifError {
                reason: atoms::error(),
                message: e.to_string(),
            })?
    } else {
        awareness.reference.update().map_err(|e| NifError {
            reason: atoms::error(),
            message: e.to_string(),
        })?
    };

    Ok(encode_binary_slice_to_term(
        env,
        update.encode_v1().as_slice(),
    ))
}
#[rustler::nif]
pub fn awareness_apply_update_v1(
    env: Env<'_>,
    awareness: NifAwareness,
    update: Binary,
    origin: Option<&str>,
) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        let update = AwarenessUpdate::decode_v1(update.as_slice())?;

        if let Some(origin) = origin {
            awareness
                .reference
                .apply_update_with(update, origin)
                .map_err(|e| NifError {
                    reason: atoms::error(),
                    message: e.to_string(),
                })
        } else {
            awareness
                .reference
                .apply_update(update)
                .map_err(|e| NifError {
                    reason: atoms::error(),
                    message: e.to_string(),
                })
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
