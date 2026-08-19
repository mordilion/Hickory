# Deployment & Release Process

## Versioning

- Single source of truth: `version:` in `pubspec.yaml` (format `X.Y.Z+build`).
- Release notes source: `CHANGELOG.md`, Keep-a-Changelog format. Entries live under `[Unreleased]` during development and get moved into a new `## [X.Y.Z] - YYYY-MM-DD` section when releasing.

## Release steps

1. Set the new version in `pubspec.yaml`.
2. Move the relevant `[Unreleased]` entries in `CHANGELOG.md` into a new `## [X.Y.Z] - YYYY-MM-DD` section.
3. Push a Git tag `vX.Y.Z` — this triggers `.github/workflows/release.yml`.

## CI: `.github/workflows/release.yml` (trigger: tag push `v*`)

- **verify-version**: fails the run if the pushed tag version doesn't match `pubspec.yaml`'s version.
- **build-macos**: `flutter build macos --release`, zips `hickory.app` → `hickory-macos.zip`, computes `hickory-macos.zip.sha256`.
- **build-windows**: `flutter build windows --release`, zips the release folder → `hickory-windows.zip`, computes `hickory-windows.zip.sha256`.
- **publish** (needs both builds): downloads both artifacts, extracts the matching version section from `CHANGELOG.md` via `awk` as release notes, publishes a GitHub Release (name = tag) with the ZIPs + checksum files attached.
- Android/iOS are **not** built or published by this workflow.

## CI: `.github/workflows/build.yml` (trigger: push to `main`, manual)

- Analyze, test, and build macOS, Windows, Android, and iOS artifacts. No GitHub Release is published — this is verification-only CI, separate from the release pipeline.

## In-app auto-update

- Implemented in `lib/core/update/` (`UpdateChecker`, `UpdateInstaller`) with providers in `lib/core/di/update_providers.dart`.
- Checks GitHub Releases on app startup and via the "Check for updates" button in Settings (`lib/features/settings/settings_screen.dart`).
- On update: downloads the platform ZIP, verifies its SHA256 checksum against the `.sha256` file from the release, extracts, and swaps the installation.
- Only wired up for macOS/Windows (`Platform.isMacOS || Platform.isWindows` gate in the settings screen) — matches the platforms actually built by the release workflow.

## macOS auto-update is blocked by the App Sandbox (found 2026-08-19)

- The app ships `com.apple.security.app-sandbox` in both entitlement files, so it may only
  write inside `~/Library/Containers/com.hickory.hickory`. `/Applications` is denied
  regardless of bundle ownership or `admin` group membership — verified on an admin account
  owning the bundle, where the same `mkdir` succeeds from a shell and fails from the app.
- `UpdateInstallPermissionException` is therefore the *normal* macOS outcome, not an edge
  case, and its old message ("move the app somewhere writable") named a place that does not
  exist under the sandbox. Corrected to point at the manual download.
- Removing the write probe would not help: `quitAndSwap`'s detached script is a child of the
  sandboxed app and inherits the sandbox.
- Fix decided: drop the sandbox, which forces a data migration out of the container because
  `getApplicationSupportDirectory()` resolves there today and nothing exists outside it. See
  `docs/superpowers/specs/2026-08-19-macos-sandbox-removal-design.md`. Keychain access for
  Jira/Personio credentials is an open risk to verify against a copied container before
  release.
- The migration cannot ship through the built-in updater: the installed sandboxed build is
  what cannot install it. That one update has to be manual.

## Gotchas

- Tag version and `pubspec.yaml` version must match exactly (`vX.Y.Z` vs `X.Y.Z`) or `verify-version` blocks the whole pipeline.
- The `awk` changelog extraction in `publish` depends on the `## [X.Y.Z]` heading existing in `CHANGELOG.md` *before* the tag is pushed — release notes will be empty otherwise.
- `UpdateInstaller.quitAndSwap` swaps the install directory from a *detached* shell/PowerShell script that only runs after the app process has fully exited — it has no way to report failure back to the Flutter UI. Because of this, `prepareUpdate()` verifies write access to the install directory's parent *before* the app quits (probes by creating+deleting a throwaway directory there); a failure throws `UpdateInstallPermissionException`, which the Settings screen shows as a specific, actionable message instead of the generic install-failed one. Without this check, a permission failure (e.g. `/Applications` on a non-admin macOS account) made the relaunch script's swap fail silently and its unconditional `open`/`Start-Process` at the end just relaunched the unchanged old app — from the user's perspective, "the app closes and immediately reopens" with no error and no update applied.

## Signing & notarization (planned, v1.3 — blocked on account/certificate acquisition)

Roadmap item, see `ROADMAP.md`. Neither the Apple Developer Program membership nor a
Windows signing certificate exists yet (as of 2026-08-13) — `release.yml` still ships
unsigned builds. Decision (2026-08-13): pursue the free-first options below before
spending money; `release.yml` itself is not changed until the relevant credentials
actually exist, so any signing steps can be tested against a real submission instead of
merged blind.

### macOS

**No-cost interim mitigation (actionable now, doesn't require the Apple fee):**

1. Publish a self-hosted Homebrew tap (e.g. `mordilion/homebrew-hickory`) with a Cask
   definition for `hickory.app`.
2. Give the Cask a `postflight` block that runs `xattr -cr` on the installed app, so
   `brew install --cask mordilion/hickory/hickory` users never see the Gatekeeper
   "damaged" dialog at all — the app is de-quarantined before first launch.
3. Document the Homebrew install as the primary path in the README; keep the direct
   ZIP download + manual `xattr -cr` instructions as the fallback for non-Homebrew users.
4. This does **not** replace real signing/notarization — it only helps Homebrew users.
   Direct-download users still hit Gatekeeper, and the app still isn't verified by Apple.
   `[inferred]` — the official `homebrew-cask` repo has gotten stricter about
   Gatekeeper-bypassing casks over time, which is why this uses a self-hosted tap rather
   than submitting to the main cask repo; re-check current homebrew-cask policy if
   submitting there is ever reconsidered.

**Full fix (needs the $99/year Apple Developer Program fee — not started, no funding
plan yet):**

1. Enroll in the Apple Developer Program (99 USD/year,
   `developer.apple.com/programs/enroll`). Identity verification takes a few days for an
   individual account, longer for an organization account (needs a D-U-N-S number).
2. Create a "Developer ID Application" certificate (for distribution outside the Mac App
   Store), export it as `.p12`, base64-encode it for storage as a GitHub secret.
3. Create an App Store Connect API key for `notarytool` (preferred over an app-specific
   password — doesn't expire on password changes).
4. GitHub secrets needed: `APPLE_CERTIFICATE_P12_BASE64`, `APPLE_CERTIFICATE_PASSWORD`,
   `APPLE_TEAM_ID`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, `APPLE_API_KEY_P8_BASE64`.
5. Future `build-macos` steps (not yet implemented): import the certificate into a
   temporary keychain → `codesign --options runtime` the `.app` → zip → `xcrun notarytool
   submit --wait` → `xcrun stapler staple` → re-zip the stapled app.

### Windows

**Primary plan: SignPath.io Foundation (free code signing for qualifying OSS
projects).** Chosen over Azure Trusted Signing specifically because it's free — apply,
don't pay, unless the application is rejected. `[verified 2026-08-13]` against
signpath.org and docs.signpath.io.

1. Apply at [signpath.org/apply](https://signpath.org/apply). Eligibility (per
   [signpath.org/terms.html](https://signpath.org/terms.html)): OSI-approved license
   without commercial dual-licensing (Hickory is MIT — qualifies), no proprietary
   components, actively maintained, already released in the form to be signed (Hickory
   already ships GitHub Releases), and the functionality must be documented on the
   download page (README already covers this).
2. **Trade-off to accept before applying:** the certificate is issued to *SignPath
   Foundation*, not to Hickory/mordilion — Windows will show "SignPath Foundation" as the
   publisher in the SmartScreen/properties dialog, not Hickory's own name. SignPath
   Foundation can also pause/revoke the certificate if their code of conduct is violated.
3. If accepted: install the [SignPath GitHub App](https://github.com/apps/signpath) on
   the repo (required for source/build policy verification), add it to a SignPath
   organization, link it to a SignPath Project for GitHub, and configure a signing
   policy — SignPath provides the org id/project slug/policy slug during onboarding.
4. GitHub secret needed: `SIGNPATH_API_TOKEN` (issued by SignPath).
5. Future `build-windows` steps (not yet implemented, see
   [docs.signpath.io/trusted-build-systems/github](https://docs.signpath.io/trusted-build-systems/github)):
   upload `hickory.exe` via `actions/upload-artifact`, then submit it for signing with
   `signpath/github-action-submit-signing-request@v2`, then use the signed artifact it
   returns instead of the unsigned one when zipping. Requires all jobs leading up to the
   signing request to run on GitHub-hosted runners (already the case —
   `windows-latest`).

**Fallback if SignPath doesn't work out: Azure Trusted Signing** (paid, ~10 USD/month,
no hardware token needed, works via `azure/trusted-signing-action`).
`[inferred]` — verify current pricing/availability on Microsoft's site before
purchasing.

1. GitHub secrets needed: Azure service-principal or OIDC credentials,
   `TRUSTED_SIGNING_ACCOUNT_NAME`, `TRUSTED_SIGNING_ENDPOINT`, `CERTIFICATE_PROFILE_NAME`.
2. A classic OV/EV certificate from a CA (DigiCert, SSL.com) is a further fallback below
   that — EV needs a hardware token, which is awkward in CI without a cloud HSM, but
   gives instant SmartScreen reputation.
