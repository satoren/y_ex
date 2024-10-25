use rustler::{types::atom::nil, Encoder, Env, OwnedBinary, Term};

pub fn origin_to_term<'a>(
    env: &mut Env<'a>,
    origin: std::option::Option<&yrs::Origin>,
) -> Term<'a> {
    origin.map_or_else(
        || nil().encode(*env),
        |origin| {
            env.binary_to_term(origin.as_ref())
                .map_or_else(|| nil().encode(*env), |(term, _size)| term)
        },
    )
}
/// Converts an Erlang term to an Origin binary.
///
/// # Arguments
/// * `term` - Erlang term to convert
///
/// # Returns
/// Returns Some(OwnedBinary) if the term is not nil and can be converted,
/// None otherwise.
pub(crate) fn term_to_origin_binary(term: Term<'_>) -> Option<OwnedBinary> {
    if nil().eq(&term) {
        None
    } else {
        Some(term.to_binary())
    }
}
