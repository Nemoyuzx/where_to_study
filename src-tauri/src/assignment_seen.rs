//! Bounded business identifiers, scoped by the existing cache owner and term.
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;
const MAX_IDS: usize = 20_000;
#[derive(Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Seen {
    pub owner: String,
    pub term: String,
    pub baseline: bool,
    pub ids: BTreeSet<String>,
    pub saturated: bool,
}
impl Seen {
    pub fn observe(
        &mut self,
        owner: &str,
        term: &str,
        ids: &[String],
        restore: bool,
    ) -> Vec<String> {
        if self.owner != owner || self.term != term {
            *self = Self {
                owner: owner.into(),
                term: term.into(),
                ..Self::default()
            };
        }
        let notify = self.baseline && !restore && !self.saturated;
        let mut fresh = Vec::new();
        for id in ids {
            if self.ids.contains(id) {
                continue;
            }
            if self.ids.len() >= MAX_IDS {
                self.saturated = true;
                break;
            }
            self.ids.insert(id.clone());
            if notify {
                fresh.push(id.clone());
            }
        }
        self.baseline = true;
        fresh
    }
    pub fn valid(&self) -> bool {
        self.ids.len() <= MAX_IDS && self.ids.iter().all(|id| !id.is_empty() && id.len() <= 1024)
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn ids(values: &[&str]) -> Vec<String> {
        values.iter().map(|s| (*s).into()).collect()
    }
    #[test]
    fn baseline_restore_restart_and_deleted_reappearing_ids_do_not_notify() {
        let mut seen = Seen::default();
        assert!(seen
            .observe("owner", "term", &ids(&["a"]), false)
            .is_empty());
        assert_eq!(
            seen.observe("owner", "term", &ids(&["a", "b"]), false),
            ids(&["b"])
        );
        let mut seen: Seen = serde_json::from_slice(&serde_json::to_vec(&seen).unwrap()).unwrap();
        assert!(seen.observe("owner", "term", &[], false).is_empty());
        assert!(seen
            .observe("owner", "term", &ids(&["a", "b", "c"]), true)
            .is_empty());
        assert!(seen
            .observe("owner", "term", &ids(&["a", "b", "c"]), false)
            .is_empty());
        assert!(seen
            .observe("other", "term", &ids(&["d"]), false)
            .is_empty());
        assert!(seen
            .observe("other", "new-term", &ids(&["e"]), false)
            .is_empty());
    }
    #[test]
    fn saturation_is_bounded_and_never_realerts_evicted_ids() {
        let mut seen = Seen::default();
        let all: Vec<_> = (0..MAX_IDS).map(|i| i.to_string()).collect();
        seen.observe("owner", "term", &all, false);
        assert!(seen
            .observe("owner", "term", &ids(&["overflow"]), false)
            .is_empty());
        assert!(seen
            .observe("owner", "term", &ids(&["overflow"]), false)
            .is_empty());
        assert_eq!(seen.ids.len(), MAX_IDS);
    }
}
