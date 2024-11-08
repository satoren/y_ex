use rustler::{Env, ResourceArc};
use std::sync::Mutex;
use yrs::*;

use crate::{error::NifError, wrap::NifWrap, ENV};

pub type SubscriptionResource = NifWrap<Mutex<Option<Subscription>>>;
#[rustler::resource_impl]
impl rustler::Resource for SubscriptionResource {}

#[rustler::nif]
fn sub_unsubscribe(env: Env<'_>, sub: ResourceArc<SubscriptionResource>) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        let mut inner = match sub.0.lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        *inner = None;
        Ok(())
    })
}
