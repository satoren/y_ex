//! Generic read-only format event observation; no domain authorization.
use crate::{any::NifAny, doc::NifDoc, transaction::TransactionResource};
use rustler::{Atom, Binary, NifResult, ResourceArc, Term};
use yrs::{
    branch::BranchID,
    format_event::{FormatEvent, FormatTarget},
    ID,
};

#[derive(Clone, rustler::NifMap)]
struct ItemID {
    client: u64,
    clock: u32,
}
impl From<ID> for ItemID {
    fn from(id: ID) -> Self {
        Self {
            client: id.client,
            clock: id.clock,
        }
    }
}
#[derive(rustler::NifMap)]
struct Target {
    root: Option<String>,
    nested: Option<ItemID>,
    item: ItemID,
}
#[derive(rustler::NifMap)]
struct State {
    marker: Option<ItemID>,
    value: NifAny,
}
#[derive(rustler::NifMap)]
struct Change {
    target_index: usize,
    before: State,
    after: State,
}
#[derive(rustler::NifMap)]
struct Event {
    inserted: Vec<ItemID>,
    deleted: Vec<ItemID>,
    changes: Vec<Change>,
}

#[rustler::nif(schedule = "DirtyCpu")]
fn inspect_format_event(
    doc: NifDoc,
    current_transaction: Option<ResourceArc<TransactionResource>>,
    update: Binary,
    attribute: String,
    targets: Term,
    max_steps: usize,
) -> NifResult<(Atom, Event)> {
    let mut requested = Vec::new();
    let mut rest = targets;
    while !rest.is_empty_list() {
        if requested.len() >= 131072 {
            return Err(rustler::Error::Atom("format_event_limit"));
        }
        let (head, tail) = rest.list_get_cell()?;
        rest = tail;
        let target: Target = head.decode()?;
        let branch = match (target.root, target.nested) {
            (Some(root), None) if !root.is_empty() && root.len() <= 256 => {
                BranchID::Root(root.into())
            }
            (None, Some(id)) => BranchID::Nested(ID::new(id.client, id.clock)),
            _ => return Err(rustler::Error::BadArg),
        };
        requested.push(FormatTarget {
            branch,
            item: ID::new(target.item.client, target.item.clock),
        });
    }
    let indexes: std::collections::HashMap<_, _> = requested
        .iter()
        .enumerate()
        .map(|(index, target)| (target.clone(), index))
        .collect();
    doc.readonly(current_transaction, |txn| {
        let event = FormatEvent::inspect(txn, update.as_slice(), &attribute, &requested, max_steps)
            .map_err(|error| rustler::Error::Term(Box::new(error.to_string())))?;
        let changes = event
            .changes
            .into_iter()
            .map(|change| {
                let target_index = *indexes.get(&change.target).expect("validated target");
                Change {
                    target_index,
                    before: State {
                        marker: change.before.marker.map(Into::into),
                        value: change.before.value.into(),
                    },
                    after: State {
                        marker: change.after.marker.map(Into::into),
                        value: change.after.value.into(),
                    },
                }
            })
            .collect();
        Ok((
            crate::atoms::ok(),
            Event {
                inserted: event.inserted.into_iter().map(Into::into).collect(),
                deleted: event.deleted.into_iter().map(Into::into).collect(),
                changes,
            },
        ))
    })
}
