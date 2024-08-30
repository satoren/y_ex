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
        if let Ok(mut sub) = sub.0.lock() {
            *sub = None;
            Ok(())
        } else {
            Err(NifError::Message("Failed to unsubscribe".to_string()))
        }
    })
}
