/// Declares a NIF and its `DirtyCpu` twin, both calling the same implementation.
///
/// Elixir picks the twin for large inputs (`Yex.Nif.dirty_cutoff/0`), or after the normal
/// NIF returned `:dirty` because the document is too large to work on within a
/// normal-scheduler time slice. With `+ [limit: Option<_>]` after the argument list, the
/// normal NIF takes that extra limit argument and the twin passes `None` (no limit).
///
/// The arguments are passed through as raw tokens because `#[rustler::nif]` rejects
/// argument types that arrive as `$ty` fragments.
///
/// ```ignore
/// nif_with_dirty_twin! {
///     /// Docs for the normal NIF.
///     fn merge_updates_v1<'a> / merge_updates_v1_dirty(
///         env: Env<'a>,
///         updates: Vec<Binary<'a>>,
///     ) -> NifResult<Term<'a>> = merge_updates_v1_impl(env, updates);
/// }
/// ```
// `#[rustler::nif]` passes the `Env` argument by its name to a wrapper it declares
// itself, so `env` has to be spelled inside this macro for the two to resolve to each other.
macro_rules! nif_with_dirty_twin {
    (
        $(#[$meta:meta])*
        fn $name:ident $(<$lt:lifetime>)? / $dirty:ident (env: Env<$elt:lifetime>, $($sig:tt)*)
            + [$limit:ident: $($limit_ty:tt)+]
            -> $ret:ty = $imp:ident(env $(, $call:ident)*);
    ) => {
        $(#[$meta])*
        #[rustler::nif]
        fn $name $(<$lt>)? (env: Env<$elt>, $($sig)* $limit: $($limit_ty)+) -> $ret {
            $imp(env, $($call,)* $limit)
        }

        #[rustler::nif(schedule = "DirtyCpu")]
        fn $dirty $(<$lt>)? (env: Env<$elt>, $($sig)*) -> $ret {
            $imp(env, $($call,)* None)
        }
    };
    (
        $(#[$meta:meta])*
        fn $name:ident $(<$lt:lifetime>)? / $dirty:ident (env: Env<$elt:lifetime>, $($sig:tt)*)
            -> $ret:ty = $imp:ident(env $(, $call:ident)*);
    ) => {
        $(#[$meta])*
        #[rustler::nif]
        fn $name $(<$lt>)? (env: Env<$elt>, $($sig)*) -> $ret {
            $imp(env, $($call),*)
        }

        #[rustler::nif(schedule = "DirtyCpu")]
        fn $dirty $(<$lt>)? (env: Env<$elt>, $($sig)*) -> $ret {
            $imp(env, $($call),*)
        }
    };
    (
        $(#[$meta:meta])*
        fn $name:ident $(<$lt:lifetime>)? / $dirty:ident ($($sig:tt)*)
            + [$limit:ident: $($limit_ty:tt)+]
            -> $ret:ty = $imp:ident($($call:ident),*);
    ) => {
        $(#[$meta])*
        #[rustler::nif]
        fn $name $(<$lt>)? ($($sig)* $limit: $($limit_ty)+) -> $ret {
            $imp($($call,)* $limit)
        }

        #[rustler::nif(schedule = "DirtyCpu")]
        fn $dirty $(<$lt>)? ($($sig)*) -> $ret {
            $imp($($call,)* None)
        }
    };
    (
        $(#[$meta:meta])*
        fn $name:ident $(<$lt:lifetime>)? / $dirty:ident ($($sig:tt)*)
            -> $ret:ty = $imp:ident($($call:ident),*);
    ) => {
        $(#[$meta])*
        #[rustler::nif]
        fn $name $(<$lt>)? ($($sig)*) -> $ret {
            $imp($($call),*)
        }

        #[rustler::nif(schedule = "DirtyCpu")]
        fn $dirty $(<$lt>)? ($($sig)*) -> $ret {
            $imp($($call),*)
        }
    };
}

mod any;
mod array;
mod atoms;
mod awareness;
mod deferred;
mod doc;
mod error;
mod event;
mod map;
mod shared_type;
mod snapshot;
mod sticky_index;
mod subscription;
mod sync;
mod term_box;
mod text;
mod transaction;
mod undo;
mod utils;
mod weak;
mod wire;
mod wrap;
mod xml;
mod yinput;
mod youtput;

use any::NifAny;
use array::NifArray;
use doc::NifDoc;
use error::Error;
use map::NifMap;
use rustler::{Env, NifStruct};
use scoped_thread_local::scoped_thread_local;
use text::NifText;
use weak::NifWeakLink;

scoped_thread_local!(
  pub static ENV: for<'a> Env<'a>
);

pub trait TryInto<T>: Sized {
    type Error;

    // Required method
    fn try_into(self) -> Result<T, Self::Error>;
}

#[derive(NifStruct)]
#[module = "Yex.UndefinedRef"]
pub struct NifUndefinedRef {
    // not supported yet or...?
    doc: NifDoc,
}

rustler::init!("Elixir.Yex.Nif");
