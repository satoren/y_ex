use rustler::{Atom, Env, NifResult, ResourceArc};
use std::sync::Mutex;
use yrs::*;

use crate::{atoms, wrap::NifWrap, ENV};

pub type SubscriptionResource = NifWrap<Mutex<Option<Subscription>>>;
#[rustler::resource_impl]
impl rustler::Resource for SubscriptionResource {}

#[rustler::nif]
fn sub_unsubscribe(env: Env<'_>, sub: ResourceArc<SubscriptionResource>) -> NifResult<Atom> {
    ENV.set(&mut env.clone(), || {
        if let Ok(mut sub) = sub.0.lock() {
            *sub = None;
            Ok(atoms::ok())
        } else {
            Err(rustler::Error::Atom("error"))
        }
    })
}
