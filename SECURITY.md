# Security

ScrubJay ships a privileged helper that runs as root, so security reports are
taken seriously and handled privately first.

## Reporting

Use GitHub's [private vulnerability
reporting](https://github.com/openwhale-labs/scrubjay/security/advisories/new)
rather than a public issue. A useful report says what an attacker controls,
what they gain, and the steps to reproduce.

Expect an acknowledgement within a few days. Fixes ship as a new release with
the issue described once users can update.

## What is in scope

The helper (`Helper/main.swift`) is the highest-value target. It holds to four
rules, documented in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#the-privileged-helper):

1. The destination and resulting ownership come from the XPC connection's
   audit token, never from the request.
2. Every filesystem operation runs against descriptors opened with
   `O_NOFOLLOW`, never against path strings that could be swapped after a
   check.
3. Sources must be direct children of an allow-listed root, or a whole `.app`
   bundle under `/Applications`.
4. The helper moves items to the Trash; it never deletes.

Anything that breaks one of these is in scope, as is any path by which an
unsigned or third-party process can reach the helper's XPC service.

Also in scope: matching logic that would attribute another app's files to the
target, since that turns a correct removal into a wrong one.

## What is not

- The app is not sandboxed. It reads `~/Library` and `/Library` by design.
- Requiring an administrator password to enable the helper is macOS's
  approval flow, not a bypassable check.
- Reports that ScrubJay can delete files. That is the product; the safeguards
  are that everything goes to the Trash and loosely matched items are never
  selected for you.
