use std::{collections::HashMap, sync::Arc, sync::Mutex};

use crate::error::Error;
use crate::subscription::{AwarenessEvent, NifSubscription, SubscriptionKey};
use crate::term_box::TermBox;
use crate::utils::{client_id, origin_to_term, term_to_origin_binary, MAX_CLIENT_ID};
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
    encoding::read::{Cursor, Error as ReadError, Read},
    sync::{awareness::AwarenessUpdateEntry, Awareness, AwarenessUpdate},
    updates::encoder::Encode,
};

pub type AwarenessResource = NifWrap<Mutex<Awareness>>;
#[rustler::resource_impl]
impl rustler::Resource for AwarenessResource {}

#[derive(NifStruct)]
#[module = "Yex.Awareness"]
pub struct NifAwareness {
    pub reference: ResourceArc<AwarenessResource>,
    doc: NifDoc,
}

impl NifAwareness {
    pub(crate) fn lock(&self) -> std::sync::MutexGuard<'_, Awareness> {
        self.reference
            .0
            .lock()
            .unwrap_or_else(|err| err.into_inner())
    }
}

#[derive(NifMap)]
pub struct NifAwarenessUpdateSummary {
    /// New clients added as part of the update.
    pub added: Vec<u64>,
    /// Existing clients that have been changed by the update.
    pub updated: Vec<u64>,
    /// Existing clients that have been removed by the update.
    pub removed: Vec<u64>,
}

fn client_ids_to_u64(ids: &[ClientID]) -> Vec<u64> {
    ids.iter().map(ClientID::get).collect()
}

#[rustler::nif]
fn awareness_new(doc: NifDoc) -> NifAwareness {
    let awareness = Awareness::new(doc.reference.doc.clone());
    let resource = AwarenessResource::from(Mutex::new(awareness));
    NifAwareness {
        reference: ResourceArc::new(resource),
        doc,
    }
}

#[rustler::nif]
fn awareness_client_id(awareness: NifAwareness) -> u64 {
    awareness.lock().client_id().get()
}
#[rustler::nif]
fn awareness_get_client_ids(awareness: NifAwareness) -> Vec<u64> {
    awareness
        .lock()
        .iter()
        .filter_map(|(id, state)| {
            if state.data.is_some() {
                Some(id.get())
            } else {
                None
            }
        })
        .collect()
}
#[rustler::nif]
fn awareness_get_states(awareness: NifAwareness) -> HashMap<u64, NifAny> {
    awareness
        .lock()
        .iter()
        .filter_map(|(id, state)| {
            if let Some(data) = state.data {
                match serde_json::from_str::<yrs::Any>(&data) {
                    Ok(any) => Some((id.get(), any.into())),
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
    awareness.lock().local_state().map(|a: yrs::Any| a.into())
}
#[rustler::nif]
fn awareness_set_local_state(
    env: Env<'_>,
    awareness: NifAwareness,
    json: NifAny,
) -> NifResult<Atom> {
    ENV.set(&mut env.clone(), || {
        awareness
            .lock()
            .set_local_state(json.0)
            .map(|_| atoms::ok())
            .map_err(|e| Error::from(e).into())
    })
}

#[rustler::nif]
fn awareness_clean_local_state(env: Env<'_>, awareness: NifAwareness) -> NifResult<Atom> {
    ENV.set(&mut env.clone(), || {
        awareness.lock().clean_local_state();
        Ok(atoms::ok())
    })
}

#[rustler::nif]
fn awareness_monitor_update(
    awareness: NifAwareness,
    pid: LocalPid,
    metadata: Term<'_>,
) -> NifSubscription {
    let (sub_key, state) = SubscriptionKey::new((pid, TermBox::new(metadata)));
    awareness
        .lock()
        .on_update(sub_key.key.clone(), move |_awareness, event, origin| {
            let Some(state) = state.get() else {
                return;
            };
            let (pid, metadata) = &*state;
            let summary = NifAwarenessUpdateSummary {
                added: client_ids_to_u64(event.added()),
                updated: client_ids_to_u64(event.updated()),
                removed: client_ids_to_u64(event.removed()),
            };
            ENV.with(|env| {
                let metadata = metadata.get(*env);
                let _ = env.send(
                    pid,
                    (
                        atoms::awareness_update(),
                        summary,
                        origin_to_term(env, origin),
                        metadata,
                    ),
                );
            })
        });
    NifSubscription::new(
        sub_key.awareness(awareness.reference.clone(), AwarenessEvent::Update),
        awareness.doc.clone(),
    )
}

#[rustler::nif]
fn awareness_monitor_change(
    awareness: NifAwareness,
    pid: LocalPid,
    metadata: Term<'_>,
) -> NifSubscription {
    let (sub_key, state) = SubscriptionKey::new((pid, TermBox::new(metadata)));
    awareness
        .lock()
        .on_change(sub_key.key.clone(), move |_awareness, event, origin| {
            let Some(state) = state.get() else {
                return;
            };
            let (pid, metadata) = &*state;
            let summary = NifAwarenessUpdateSummary {
                added: client_ids_to_u64(event.added()),
                updated: client_ids_to_u64(event.updated()),
                removed: client_ids_to_u64(event.removed()),
            };
            ENV.with(|env| {
                let metadata = metadata.get(*env);
                let _ = env.send(
                    pid,
                    (
                        atoms::awareness_change(),
                        summary,
                        origin_to_term(env, origin),
                        metadata,
                    ),
                );
            })
        });
    NifSubscription::new(
        sub_key.awareness(awareness.reference.clone(), AwarenessEvent::Change),
        awareness.doc.clone(),
    )
}

#[rustler::nif]
pub fn awareness_encode_update_v1(
    env: Env<'_>,
    awareness: NifAwareness,
    clients: Option<Vec<u64>>,
) -> NifResult<Term<'_>> {
    let awareness = awareness.lock();
    let update = if let Some(clients) = clients {
        let clients = clients
            .into_iter()
            .map(client_id)
            .collect::<NifResult<Vec<_>>>()?;
        awareness
            .update_with_clients(clients)
            .map_err(Error::from)?
    } else {
        awareness.update().map_err(Error::from)?
    };

    Ok((
        atoms::ok(),
        SliceIntoBinary::new(update.encode_v1().as_slice()),
    )
        .encode(env))
}
/// Decodes a v1 awareness update, rejecting client ids of 2^53 or more.
///
/// yrs 0.28 `AwarenessUpdate::decode` passes the raw `u64` to `ClientID::new`, which only
/// debug-asserts the 53-bit range and masks the high bits away in release builds. A remote
/// entry for client `2^53 + n` would then overwrite or remove the state of client `n`,
/// including the local one. The wire format is `len, (client, clock, json)*`, as in yjs.
fn decode_awareness_update_v1(bytes: &[u8]) -> Result<AwarenessUpdate, ReadError> {
    let mut cursor = Cursor::new(bytes);
    let len: usize = cursor.read_var()?;
    let mut clients = HashMap::new();
    // `len` comes from the network: reserve fallibly, as yrs does.
    clients.try_reserve(len)?;
    for _ in 0..len {
        let client: u64 = cursor.read_var()?;
        if client > MAX_CLIENT_ID {
            return Err(ReadError::Custom(format!(
                "awareness client id {client} is out of range 0..{MAX_CLIENT_ID}"
            )));
        }
        let clock: u32 = cursor.read_var()?;
        let json: Arc<str> = cursor.read_string()?.into();
        clients.insert(ClientID::new(client), AwarenessUpdateEntry { clock, json });
    }
    Ok(AwarenessUpdate { clients })
}

#[rustler::nif]
pub fn awareness_apply_update_v1(
    env: Env<'_>,
    awareness: NifAwareness,
    update: Binary,
    origin: Term<'_>,
) -> NifResult<Atom> {
    ENV.set(&mut env.clone(), || {
        let update = decode_awareness_update_v1(update.as_slice()).map_err(Error::from)?;

        let mut awareness = awareness.lock();
        if let Some(origin) = term_to_origin_binary(origin) {
            awareness
                .apply_update_with(update, origin.as_slice())
                .map(|_| atoms::ok())
                .map_err(|e| Error::from(e).into())
        } else {
            awareness
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
    clients: Vec<u64>,
) -> NifResult<()> {
    // Validate every id before removing any, so a bad id leaves all states in place.
    let clients = clients
        .into_iter()
        .map(client_id)
        .collect::<NifResult<Vec<_>>>()?;
    ENV.set(&mut env.clone(), || {
        let mut awareness = awareness.lock();
        for id in clients {
            awareness.remove_state(id);
        }
    });
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use yrs::encoding::write::Write;
    use yrs::updates::decoder::Decode;

    fn encode(entries: &[(u64, u32, &str)]) -> Vec<u8> {
        let mut buf = Vec::new();
        buf.write_var(entries.len());
        for (client, clock, json) in entries {
            buf.write_var(*client);
            buf.write_var(*clock);
            buf.write_string(json);
        }
        buf
    }

    #[test]
    fn decodes_like_yrs() {
        let bytes = encode(&[(1, 3, "{\"a\":1}"), (MAX_CLIENT_ID, 1, "null")]);
        let ours = decode_awareness_update_v1(&bytes).unwrap();
        let theirs = AwarenessUpdate::decode_v1(&bytes).unwrap();
        assert_eq!(ours, theirs);
    }

    #[test]
    fn rejects_client_ids_of_2_pow_53_or_more() {
        for client in [MAX_CLIENT_ID + 1, (1 << 53) + 7, u64::MAX] {
            let bytes = encode(&[(1, 1, "{}"), (client, 2, "null")]);
            assert!(matches!(
                decode_awareness_update_v1(&bytes),
                Err(ReadError::Custom(_))
            ));
        }
    }

    #[test]
    fn truncated_input_is_an_error() {
        let bytes = encode(&[(1, 1, "{}")]);
        assert!(decode_awareness_update_v1(&bytes[..bytes.len() - 1]).is_err());
    }
}
