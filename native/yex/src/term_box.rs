use rustler::env::OwnedEnv;
use rustler::env::SavedTerm;
use rustler::Env;
use rustler::Term;

// https://github.com/rusterlium/rustler/issues/333#issuecomment-702236600

pub struct TermBox {
    inner: std::sync::Mutex<TermBoxContents>,
}

struct TermBoxContents {
    owned_env: OwnedEnv,
    saved_term: SavedTerm,
}

impl TermBox {
    pub fn new(term: Term) -> Self {
        Self {
            inner: std::sync::Mutex::new(TermBoxContents::new(term)),
        }
    }

    pub fn get<'a>(&self, env: Env<'a>) -> Term<'a> {
        let inner = match self.inner.lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };

        // Copy over term from owned environment to the target environment
        inner.owned_env.run(|inner_env| {
            let term = inner.saved_term.load(inner_env);
            term.in_env(env)
        })
    }
}

impl TermBoxContents {
    fn new(term: Term) -> Self {
        let owned_env = OwnedEnv::new();
        let saved_term = owned_env.save(term);
        Self {
            owned_env: owned_env,
            saved_term: saved_term,
        }
    }
}
