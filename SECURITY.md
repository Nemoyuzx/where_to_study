# Security Policy

## Scope and support status

Security reports are accepted for the default branch and released builds. The
repository does not currently promise a supported-version matrix, an
acknowledgement deadline, or a remediation SLA. Include the affected release,
commit, platform, and architecture so maintainers can determine the actual
scope.

Relevant areas include credential storage, authentication transport, local IPC
and Tauri commands, update or installer integrity, calendar access, dependency
vulnerabilities, and unintended disclosure of cached schedule or classroom
data.

## Reporting a vulnerability

Do not publish credentials, tokens, proof-of-concept exploit details, personal
data, or an unpatched vulnerability in a public issue.

1. If GitHub shows **Security > Advisories > Report a vulnerability** for this
   repository, use that private channel.
2. If private vulnerability reporting is unavailable, open the
   [Security contact request](https://github.com/Nemoyuzx/where_to_study/issues/new?template=security_contact.yml)
   form. Include only the affected version, a broad category, and a
   non-sensitive impact summary. A maintainer can then arrange a private
   channel before technical details are shared.

The repository currently publishes no dedicated security email address. The
contact-request issue is only a coordination mechanism, not a place for the
vulnerability report itself.

Once a private channel is available, a useful report contains:

- affected versions, commits, platforms, and configurations;
- prerequisites and reproducible steps;
- observed impact and the expected security boundary;
- a minimal proof of concept with all secrets and personal data removed;
- any known workaround or proposed fix;
- whether the issue is already public or actively exploited.

## Handling and disclosure

Maintainers will evaluate reports according to availability and impact, but no
response or fix timeline is guaranteed. Please avoid public disclosure until a
fix or mitigation can be prepared and affected users can update. Any eventual
advisory should credit reporters only with their consent.

This project does not currently publish a bug bounty, payment commitment, or
formal safe-harbor program. Nothing in this file changes applicable law or
grants authorization to access systems or data you do not own or have explicit
permission to test.

## Exposed secrets

If a real credential or signing secret is committed, do not rely on deleting
the file or rewriting history alone. Revoke or rotate the secret first, then
remove it from reachable history and assess any artifacts that were signed or
accessed with it. Report the incident through the process above without putting
the secret in an issue, log, screenshot, or attachment.

## License status

Project code is distributed under the GNU General Public License v3.0 only
(`GPL-3.0-only`); see `LICENSE`. Third-party materials retain the licenses
recorded in `THIRD_PARTY_NOTICES.md` and `THIRD_PARTY_LICENSES.html`. This
security policy does not grant any additional permissions beyond those
applicable terms.
