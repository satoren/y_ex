use std::cell::RefCell;
use yrs::*;

use crate::wrap::NifWrap;

pub type SubscriptionResource = NifWrap<RefCell<Option<Subscription>>>;
#[rustler::resource_impl]
impl rustler::Resource for SubscriptionResource {}
