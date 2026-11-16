# Code signing policy

## Current status

MA Floater's native Windows application and installer are currently unsigned development artifacts. They are not approved public releases and Windows 11 Smart App Control may block them.

The intended provider is: **Free code signing provided by SignPath.io, certificate by SignPath Foundation.** SignPath Foundation has not accepted MA Floater yet, so this statement describes the planned route rather than current signed status.

## Scope

A native Windows release is acceptable only when all executable artifacts are covered by a trusted Authenticode signing path:

- `MAFloater.exe`
- the downloadable Windows installer
- the uninstaller installed on the user's computer

The signatures must use a trusted certificate, an RFC 3161 timestamp, consistent product metadata, and a build traceable to the public repository. SHA-256 checksums are published as integrity evidence but do not replace signatures.

Unsigned workflow artifacts are retained only as short-lived development or signing inputs. They must be named `unsigned` and must not be attached to a public GitHub Release.

## Build and approval roles

MA Floater is currently maintained by [bewye99](https://github.com/bewye99), who serves as:

- Committer and reviewer
- Release approver
- Signing-request approver

Multi-factor authentication is required for every GitHub and SignPath account with repository, approval, or signing access.

## Privacy

MA Floater does not send telemetry. It connects to the Music Assistant server configured by the user and may download artwork from URLs supplied by that server. Music Assistant credentials remain on the user's computer and are protected with Windows Data Protection for the current Windows account.

## Release requirements

Before approving a native Windows release:

1. Build from a reviewed commit using the repository's GitHub Actions workflow.
2. Verify the native tests and publication checks pass.
3. Sign every executable artifact in scope and verify each signature after packaging and installation.
4. Test installation, launch, Start-menu integration, optional startup, compact/hover behavior, upgrade, and uninstall on Windows 11 with Smart App Control enabled.
5. Publish hashes for the exact signed downloads.
6. Record the source commit, workflow run, signer, signing-request identifier, and verification result in the release notes.

The current Inno Setup path has an unresolved signing requirement: the signing provider must confirm a supported method for signing the embedded application and generated uninstaller. If it cannot, the installer technology must be reconsidered before release.

## Reporting problems

Report suspected signing, release-integrity, credential, or security problems privately to the maintainer when possible. Do not publish credentials, tokens, private keys, or sensitive logs in an issue. Ordinary defects can be reported through the repository's GitHub issue tracker.
