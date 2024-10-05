use rustler::{Atom, Env, NifResult, ResourceArc};
use std::sync::Mutex;
use yrs::*;

use crate::{atoms, wrap::NifWrap, ENV};

pub type SubscriptionResource = NifWrap<Mutex<Option<Subscription>>>;
#[rustler::resource_impl]
impl rustler::Resource for SubscriptionResource {}

impl SubscriptionResource {
    pub fn arc(sub: Subscription) -> ResourceArc<Self> {
        ResourceArc::new(NifWrap(Mutex::new(Some(sub))))
    }
}

#[rustler::nif]
fn sub_unsubscribe(env: Env<'_>, sub: ResourceArc<SubscriptionResource>) -> NifResult<Atom> {
    ENV.set(&mut env.clone(), || {
        let mut inner = match sub.0.lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        *inner = None;
        Ok(atoms::ok())
    })
}
