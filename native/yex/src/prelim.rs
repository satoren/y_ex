//! `as_prelim/1` of the shared types in one call. The whole tree is read and its prelim
//! structs are built here, instead of Elixir making a call per node and per attribute map.
//!
//! The structs are the ones the Elixir `as_prelim/1` functions build, field for field:
//! a shared type becomes its prelim, recursively, and everything else is returned as it
//! reads (values, subdocuments, and the shared types embedded in a text's delta).

use std::cell::Cell;

use rustler::{Atom, Encoder, Env, NifResult, ResourceArc, Term};
use yrs::types::{text::YChange, AsPrelim};
use yrs::{
    Array, ArrayRef, Map, MapRef, Out, Text, TextRef, Xml, XmlElementRef, XmlFragmentRef, XmlOut,
    XmlTextRef,
};

use crate::{
    any::encode_str,
    atoms,
    doc::NifDoc,
    shared_type::NifSharedType,
    text::encode_diffs,
    transaction::{ReadTransaction, TransactionResource},
    wrap::{make_list, make_map},
    xml::child_xml_nodes,
    yinput::{NifSharedTypeInput, NifWeakPrelim},
    youtput::NifYOut,
};

/// One conversion. `budget` is how many more values it may convert, counting every value,
/// child node and delta entry. Once it runs out the conversion stops and its result is
/// discarded, so a normal-scheduler call is bounded however large the tree is.
struct Conversion<'a, 'r, 't, 'doc> {
    env: Env<'a>,
    txn: &'r ReadTransaction<'t, 'doc>,
    doc: &'r NifDoc,
    budget: Cell<usize>,
    exhausted: Cell<bool>,
}

impl Conversion<'_, '_, '_, '_> {
    /// Takes `n` from the budget. Returns false, and marks the conversion exhausted, when
    /// there is less.
    fn spend(&self, n: usize) -> bool {
        match self.budget.get().checked_sub(n) {
            Some(left) => {
                self.budget.set(left);
                true
            }
            None => {
                self.exhausted.set(true);
                false
            }
        }
    }

    fn exhausted(&self) -> bool {
        self.exhausted.get()
    }

    /// Enough of a collection to convert it, or to find the budget runs out.
    fn take_limit(&self) -> usize {
        self.budget.get().saturating_add(1)
    }
}

// Each nesting level of a document costs a few of these frames, and the dirty twin runs on a
// dirty scheduler, whose stack is small. So every kind is built out of line, and only the
// kinds a level holds pay for their frames.

fn as_prelim<'a>(cx: &Conversion<'a, '_, '_, '_>, out: Out) -> Term<'a> {
    if !cx.spend(1) {
        return rustler::types::atom::nil().encode(cx.env);
    }
    match out {
        Out::YText(text) => text_prelim(cx, &text),
        Out::YArray(array) => array_prelim(cx, &array),
        Out::YMap(map) => map_prelim(cx, &map),
        Out::YXmlElement(xml) => xml_element_prelim(cx, &xml),
        Out::YXmlFragment(xml) => xml_fragment_prelim(cx, &xml),
        Out::YXmlText(xml) => xml_text_prelim(cx, &xml),
        Out::YWeakLink(weak) => NifWeakPrelim::new(weak.as_prelim(cx.txn).upcast()).encode(cx.env),
        // Values, subdocuments and types with no struct are their own prelims.
        other => NifYOut::from_native(other, cx.doc).encode(cx.env),
    }
}

fn xml_as_prelim<'a>(cx: &Conversion<'a, '_, '_, '_>, out: XmlOut) -> Term<'a> {
    match out {
        XmlOut::Element(xml) => xml_element_prelim(cx, &xml),
        XmlOut::Fragment(xml) => xml_fragment_prelim(cx, &xml),
        XmlOut::Text(xml) => xml_text_prelim(cx, &xml),
    }
}

fn prelim_struct<'a, const N: usize>(
    env: Env<'a>,
    module: Atom,
    fields: [(Atom, Term<'a>); N],
) -> Term<'a> {
    let fields = fields.map(|(key, value)| (key.encode(env), value));
    let module = (atoms::struct_().encode(env), module.encode(env));
    make_map(env, std::iter::once(module).chain(fields))
}

/// A map of names to the prelims of their values.
fn entries_prelim<'a, 'b>(
    cx: &Conversion<'a, '_, '_, '_>,
    entries: impl Iterator<Item = (&'b str, Out)>,
) -> Term<'a> {
    let entries = entries.take_while(|_| !cx.exhausted());
    make_map(
        cx.env,
        entries.map(|(key, value)| (encode_str(cx.env, key), as_prelim(cx, value))),
    )
}

/// The prelims of the nodes `children/1` streams.
fn children_prelim<'a, X: yrs::XmlFragment>(cx: &Conversion<'a, '_, '_, '_>, xml: &X) -> Term<'a> {
    let children = child_xml_nodes(xml, cx.txn, cx.take_limit());
    if !cx.spend(children.len()) {
        return rustler::types::atom::nil().encode(cx.env);
    }
    make_list(
        cx.env,
        children.into_iter().map(|child| xml_as_prelim(cx, child)),
    )
}

fn delta<'a>(cx: &Conversion<'a, '_, '_, '_>, text: &impl Text) -> Term<'a> {
    let diff = text.diff(cx.txn, YChange::identity);
    if !cx.spend(diff.len()) {
        return rustler::types::atom::nil().encode(cx.env);
    }
    encode_diffs(diff, cx.doc, cx.env)
}

#[inline(never)]
fn text_prelim<'a>(cx: &Conversion<'a, '_, '_, '_>, text: &TextRef) -> Term<'a> {
    let delta = delta(cx, text);
    prelim_struct(cx.env, atoms::text_prelim(), [(atoms::delta(), delta)])
}

#[inline(never)]
fn array_prelim<'a>(cx: &Conversion<'a, '_, '_, '_>, array: &ArrayRef) -> Term<'a> {
    let items: Vec<Out> = array.iter(cx.txn).take(cx.take_limit()).collect();
    let list = make_list(cx.env, items.into_iter().map(|item| as_prelim(cx, item)));
    prelim_struct(cx.env, atoms::array_prelim(), [(atoms::list(), list)])
}

#[inline(never)]
fn map_prelim<'a>(cx: &Conversion<'a, '_, '_, '_>, map: &MapRef) -> Term<'a> {
    let entries = entries_prelim(cx, map.iter(cx.txn));
    prelim_struct(cx.env, atoms::map_prelim(), [(atoms::map(), entries)])
}

#[inline(never)]
fn xml_element_prelim<'a>(cx: &Conversion<'a, '_, '_, '_>, xml: &XmlElementRef) -> Term<'a> {
    let tag = match xml.try_tag() {
        Some(tag) => encode_str(cx.env, tag),
        None => rustler::types::atom::nil().encode(cx.env),
    };
    let attributes = entries_prelim(cx, xml.attributes(cx.txn));
    let children = children_prelim(cx, xml);
    prelim_struct(
        cx.env,
        atoms::xml_element_prelim(),
        [
            (atoms::tag(), tag),
            (atoms::attributes(), attributes),
            (atoms::children(), children),
        ],
    )
}

#[inline(never)]
fn xml_fragment_prelim<'a>(cx: &Conversion<'a, '_, '_, '_>, xml: &XmlFragmentRef) -> Term<'a> {
    let children = children_prelim(cx, xml);
    prelim_struct(
        cx.env,
        atoms::xml_fragment_prelim(),
        [(atoms::children(), children)],
    )
}

#[inline(never)]
fn xml_text_prelim<'a>(cx: &Conversion<'a, '_, '_, '_>, xml: &XmlTextRef) -> Term<'a> {
    let delta = delta(cx, xml);
    let attributes = entries_prelim(cx, xml.attributes(cx.txn));
    prelim_struct(
        cx.env,
        atoms::xml_text_prelim(),
        [(atoms::delta(), delta), (atoms::attributes(), attributes)],
    )
}

fn shared_type_as_prelim_impl<'a>(
    env: Env<'a>,
    shared_type: NifSharedTypeInput,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    budget: Option<usize>,
) -> NifResult<Term<'a>> {
    let doc = shared_type.doc_and_id().0;
    doc.readonly(current_transaction, |txn| {
        let out = match &shared_type {
            NifSharedTypeInput::Text(v) => Out::YText(v.get_ref(txn)?),
            NifSharedTypeInput::Map(v) => Out::YMap(v.get_ref(txn)?),
            NifSharedTypeInput::Array(v) => Out::YArray(v.get_ref(txn)?),
            NifSharedTypeInput::XmlText(v) => Out::YXmlText(v.get_ref(txn)?),
            NifSharedTypeInput::XmlElement(v) => Out::YXmlElement(v.get_ref(txn)?),
            NifSharedTypeInput::XmlFragment(v) => Out::YXmlFragment(v.get_ref(txn)?),
            NifSharedTypeInput::WeakLink(v) => Out::YWeakLink(v.get_ref(txn)?),
        };
        let cx = Conversion {
            env,
            txn,
            doc,
            budget: Cell::new(budget.unwrap_or(usize::MAX)),
            exhausted: Cell::new(false),
        };
        let prelim = as_prelim(&cx, out);
        Ok(if cx.exhausted() {
            atoms::dirty().encode(env)
        } else {
            prelim
        })
    })
}

/// Returns `:dirty`, discarding what it built, when the tree holds more than `budget` values.
#[rustler::nif]
fn shared_type_as_prelim<'a>(
    env: Env<'a>,
    shared_type: NifSharedTypeInput,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    budget: usize,
) -> NifResult<Term<'a>> {
    shared_type_as_prelim_impl(env, shared_type, current_transaction, Some(budget))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn shared_type_as_prelim_dirty<'a>(
    env: Env<'a>,
    shared_type: NifSharedTypeInput,
    current_transaction: Option<ResourceArc<TransactionResource>>,
) -> NifResult<Term<'a>> {
    shared_type_as_prelim_impl(env, shared_type, current_transaction, None)
}
