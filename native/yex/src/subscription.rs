use rustler::{Atom, Env, NifResult, NifStruct, ResourceArc};
use std::sync::Mutex;
use yrs::*;

use crate::{atoms, doc::NifDoc, wrap::NifWrap, ENV};

pub type SubscriptionResource = NifWrap<Mutex<Option<Subscription>>>;
#[rustler::resource_impl]
impl rustler::Resource for SubscriptionResource {}

impl SubscriptionResource {
    pub fn arc(sub: Subscription) -> ResourceArc<Self> {
        ResourceArc::new(NifWrap(Mutex::new(Some(sub))))
    }
}

#[derive(NifStruct)]
#[module = "Yex.Subscription"]
pub struct NifSubscription {
    pub(crate) reference: ResourceArc<SubscriptionResource>,
    pub(crate) doc: NifDoc,
}

#[rustler::nif]
fn sub_unsubscribe(env: Env<'_>, sub: NifSubscription) -> NifResult<Atom> {
    ENV.set(&mut env.clone(), || {
        let mut inner = match sub.reference.0.lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        *inner = None;
        Ok(atoms::ok())
    })
}
