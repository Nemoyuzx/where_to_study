//! QA-only, content-free observation of the existing auth script.
//! Tags are untrusted page metadata, never proof of identity or authorization.
use super::qa_diagnostics::Milestone;
use zeroize::Zeroizing;

// These are deliberately exact: drift must reject the whole transformation.
const REPLACEMENTS: [(&str, &str); 10] = [
    (
        r#"if(install!=='AUTH_INSTALLED'){"#,
        r#"if(install==='AUTH_INSTALLED')qaMark('INSTALL_OK');if(install!=='AUTH_INSTALLED'){qaMark('INSTALL_CONFLICT');"#,
    ),
    (
        r#"const finish=()=>{cancelled=true;"#,
        r#"const finish=()=>{qaMark('CANCELLED');cancelled=true;"#,
    ),
    (
        r#"if(Object.prototype.hasOwnProperty.call(globalThis,'WTSQmAuthPollActive')){"#,
        r#"if(Object.prototype.hasOwnProperty.call(globalThis,'WTSQmAuthPollActive')){qaMark('POLL_CONFLICT');"#,
    ),
    (
        r#"const send=report=>"#,
        r#"const send=report=>{qaMark('IPC_REQUESTED');const p="#,
    ),
    (
        r#"}).catch(finish);
              const schedule="#,
        r#"});try{p.then(()=>{qaMark('IPC_RESOLVED');},()=>{qaMark('IPC_REJECTED');});}catch{}return p.catch(finish);};
              const schedule="#,
    ),
    (
        r#"const poll=async()=>{if(cancelled)return;"#,
        r#"const poll=async()=>{if(cancelled)return;qaMark('POLL_ENTERED');"#,
    ),
    (
        r#"{finish();return;}if(++attempts>70)"#,
        r#"{qaMark('LOCATION_MISMATCH');finish();return;}if(++attempts>70)"#,
    ),
    (
        r#"{finish();return;}
                if(accountWait===true"#,
        r#"{qaMark('LOCATION_MISMATCH');finish();return;}
                if(accountWait===true"#,
    ),
    (
        r#"const report=WTSQmAuth.inspect("#,
        r#"qaMark('INSPECT_ENTERED');const report=WTSQmAuth.inspect("#,
    ),
    (
        r#";if(report.stage==='challenge')attempts=0;"#,
        r#";qaMark('INSPECT_RETURNED');if(report.stage==='challenge')attempts=0;"#,
    ),
];

const PREFIX: &str = r#"(()=>{let qaFailed=false;const qaMark=tag=>{try{if(qaFailed)return;if(!['INSTALL_OK','INSTALL_CONFLICT','POLL_CONFLICT','POLL_ENTERED','LOCATION_MISMATCH','INSPECT_ENTERED','INSPECT_RETURNED','IPC_REQUESTED','IPC_RESOLVED','IPC_REJECTED','CANCELLED'].includes(tag))return;if(['INSTALL_CONFLICT','POLL_CONFLICT','LOCATION_MISMATCH','IPC_REJECTED','CANCELLED'].includes(tag))qaFailed=true;Object.defineProperty(globalThis,'__WTS_QA_AUTH_OBSERVER_V1',{value:tag,enumerable:false,writable:false,configurable:true});}catch{}};try{Object.defineProperty(globalThis,'__WTS_QA_AUTH_OBSERVER_V1',{value:'OBSERVER_UNAVAILABLE',enumerable:false,writable:false,configurable:true});}catch{}"#;
const SUFFIX: &str = "\n;})()";

// No document, URL, storage, account, error or payload is read here. A descriptor
// value avoids executing a page-supplied accessor; Rust must still whitelist it.
pub(super) const READ_SCRIPT: &str = r#"(()=>{try{const d=Object.getOwnPropertyDescriptor(globalThis,'__WTS_QA_AUTH_OBSERVER_V1');const tag=d&&d.value;if(typeof tag!=='string')return 'OBSERVER_UNAVAILABLE';switch(tag){case 'INSTALL_OK':return 'INSTALL_OK';case 'INSTALL_CONFLICT':return 'INSTALL_CONFLICT';case 'POLL_CONFLICT':return 'POLL_CONFLICT';case 'POLL_ENTERED':return 'POLL_ENTERED';case 'LOCATION_MISMATCH':return 'LOCATION_MISMATCH';case 'INSPECT_ENTERED':return 'INSPECT_ENTERED';case 'INSPECT_RETURNED':return 'INSPECT_RETURNED';case 'IPC_REQUESTED':return 'IPC_REQUESTED';case 'IPC_RESOLVED':return 'IPC_RESOLVED';case 'IPC_REJECTED':return 'IPC_REJECTED';case 'CANCELLED':return 'CANCELLED';default:return 'OBSERVER_UNAVAILABLE';}}catch{return 'OBSERVER_UNAVAILABLE';}})()"#;

pub(super) fn milestone(result: &str) -> Milestone {
    match result {
        "\"INSTALL_OK\"" => Milestone::AuthObserverInstallOk,
        "\"INSTALL_CONFLICT\"" => Milestone::AuthObserverInstallConflict,
        "\"POLL_CONFLICT\"" => Milestone::AuthObserverPollConflict,
        "\"POLL_ENTERED\"" => Milestone::AuthObserverPollEntered,
        "\"LOCATION_MISMATCH\"" => Milestone::AuthObserverLocationMismatch,
        "\"INSPECT_ENTERED\"" => Milestone::AuthObserverInspectEntered,
        "\"INSPECT_RETURNED\"" => Milestone::AuthObserverInspectReturned,
        "\"IPC_REQUESTED\"" => Milestone::AuthObserverIpcRequested,
        "\"IPC_RESOLVED\"" => Milestone::AuthObserverIpcResolved,
        "\"IPC_REJECTED\"" => Milestone::AuthObserverIpcRejected,
        "\"CANCELLED\"" => Milestone::AuthObserverCancelled,
        _ => Milestone::AuthObserverUnavailable,
    }
}

pub(super) fn transform(script: &str) -> Option<Zeroizing<String>> {
    if REPLACEMENTS
        .iter()
        .any(|(needle, _)| script.matches(*needle).count() != 1)
    {
        return None;
    }
    let mut observed = Zeroizing::new(script.to_owned());
    for (needle, replacement) in REPLACEMENTS {
        // Zeroize each old allocation, including the interpolated account hint.
        observed = Zeroizing::new(observed.replacen(needle, replacement, 1));
    }
    Some(Zeroizing::new(format!(
        "{PREFIX}{}{SUFFIX}",
        observed.as_str()
    )))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn callback_mapping_accepts_only_exact_fixed_json_strings() {
        assert_eq!(
            milestone("\"IPC_REQUESTED\""),
            Milestone::AuthObserverIpcRequested
        );
        assert_eq!(
            milestone("\"IPC_RESOLVED\""),
            Milestone::AuthObserverIpcResolved
        );
        assert_eq!(
            milestone("\"IPC_REJECTED\""),
            Milestone::AuthObserverIpcRejected
        );
        for result in [
            "IPC_REQUESTED",
            "null",
            "{}",
            "\"private text\"",
            " \"IPC_RESOLVED\"",
            "\"OBSERVER_UNAVAILABLE\"",
        ] {
            assert_eq!(milestone(result), Milestone::AuthObserverUnavailable);
        }
    }

    #[test]
    fn needles_are_unique_and_all_or_nothing() {
        let fixture = REPLACEMENTS
            .iter()
            .map(|(needle, _)| *needle)
            .collect::<Vec<_>>()
            .join("\n");
        assert!(transform(&fixture).is_some());
        for (needle, _) in REPLACEMENTS {
            assert!(transform(&fixture.replacen(needle, "", 1)).is_none());
            assert!(transform(&format!("{fixture}{needle}")).is_none());
        }
    }
}
