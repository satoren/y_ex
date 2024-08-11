use rustler::{Env, ResourceArc};
use std::cell::RefCell;
use yrs::*;

use crate::{error::NifError, wrap::NifWrap, ENV};

pub type SubscriptionResource = NifWrap<RefCell<Option<Subscription>>>;
#[rustler::resource_impl]
impl rustler::Resource for SubscriptionResource {}

#[rustler::nif]
fn sub_unsubscribe(env: Env<'_>, sub: ResourceArc<SubscriptionResource>) -> Result<(), NifError> {
    ENV.set(&mut env.clone(), || {
        *sub.borrow_mut() = None;
        Ok(())
    })
}
