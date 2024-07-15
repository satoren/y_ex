use std::cell::RefCell;
use yrs::*;

use crate::wrap::NifWrap;

pub type SubscriptionResource = NifWrap<RefCell<Option<Subscription>>>;
