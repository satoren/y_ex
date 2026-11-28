use rustler::{Encoder, Env, LocalPid, Term};
use scoped_thread_local::scoped_thread_local;
use yrs::Origin;

use crate::subscription::NifSubscription;

/// Messages that observers of the listed subscriptions would have sent, collected
/// instead while `collect` runs.
pub(crate) struct Capture<'a> {
    env: Env<'a>,
    keys: Vec<Origin>,
    messages: Vec<Term<'a>>,
}

scoped_thread_local!(
  static CAPTURE: for<'a> Capture<'a>
);

/// Runs `f`, and returns with its result the messages that the observers of `subs` sent
/// meanwhile, in the order they were sent. Those messages are not sent.
///
/// A process that applies an update and then handles the events it caused would otherwise
/// have to fish them out of its own mailbox with a selective receive: they arrive behind
/// everything already queued, so each receive scans the whole backlog.
pub(crate) fn collect<'a, R>(
    env: Env<'a>,
    subs: &[NifSubscription],
    f: impl FnOnce() -> R,
) -> (R, Vec<Term<'a>>) {
    let mut capture = Capture {
        env,
        keys: subs.iter().map(NifSubscription::key).collect(),
        messages: Vec::new(),
    };
    let result = CAPTURE.set(&mut capture, f);
    (result, capture.messages)
}

/// Sends the message `make` builds to `pid`, or, while `collect` runs for the subscription
/// `key`, adds it to the collected messages instead.
pub(crate) fn send_or_capture<F>(env: Env<'_>, key: &Origin, pid: &LocalPid, make: F)
where
    F: for<'b> FnOnce(Env<'b>) -> Term<'b>,
{
    if CAPTURE.is_set() && CAPTURE.with(|capture| capture.keys.contains(key)) {
        CAPTURE.with(|capture| {
            let message = make(capture.env);
            capture.messages.push(message);
        });
        return;
    }
    let message = make(env);
    let _ = env.send(pid, message.encode(env));
}
