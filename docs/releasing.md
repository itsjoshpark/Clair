# Releasing Clair

A release runs from `main` through `.github/workflows/release.yml`, mostly on the owner's Mac. It works out the version, makes sure the commit has an engine and passing quality checks, packages and notarizes the app, and publishes it. `main` gets the appcast last, so no entry points at a file that doesn't exist yet.

## Before you start

- **Notes:** `.changes/unreleased/` needs at least one Changie fragment. User-facing pull requests add their own; see [`.changes/README.md`](../.changes/README.md).
- **Runner:** the owner's Mac must be online, with its runner started (`./run.sh`).
- **Certificate:** the Developer ID certificate expires on 2027-02-01. The release warns in the last 30 days and stops once it has expired.

## Start a release

```sh
gh workflow run release.yml -f release-type=auto                 # the bump comes from the fragments
gh workflow run release.yml -f release-type=minor                # or choose it
gh workflow run release.yml -f release-type=auto -f dry-run=true # build and notarize only
```

With `auto`, a `New` fragment bumps the minor version and the other kinds bump the patch. The MVP becomes `1.0.0` with `major`.

| Job | Runs on | What it does |
|---|---|---|
| `validate` | Mac | Refuses a run with no fragments, an existing tag or notes, a build number Sparkle wouldn't offer, or notes that won't render |
| `engine` | Mac | Builds the engine only if `chromium-engine-<key>` isn't published, which can take about 4 hours |
| `quality` | Hosted | Runs the quality checks only if they haven't already passed for the commit |
| `package` | Mac, `release` environment | Checks the credentials, then signs, notarizes and staples the app and the DMG, verifies them, makes the deltas and signs every asset |
| `publish` | Mac, `release` environment | Makes the release commit, tags it, creates the GitHub Release, and pushes to `main` |

A dry run stops after `package` and leaves the DMG as a workflow artifact. It adds no tag, Release or appcast change.

If `main` moves before the Release is created, `publish` stops with nothing published, so run the release again. If a run fails after the Release exists, its error says how to get the appcast onto `main`.

## Manual release checklist

The quality checks can't cover these, so run them on the dry-run DMG, on a clean Mac or user account:

- [ ] The notarized DMG opens after only the standard downloaded-from-the-internet prompt
- [ ] A CRX installs through the extension MIME flag
- [ ] ungoogled-chromium's default settings are in place
- [ ] System Settings lists Clair as a default browser, and a link from another app opens in it
- [ ] The update path works with Developer ID-signed builds: a delta downloads in the background, Restart and Update restores the session, quitting installs the update, and so do 30 idle minutes
- [ ] Sparkle rejects a release signed by a different team

## Secrets

The `release` environment is limited to `main`, and only the `package` and `publish` jobs use it. `.github/workflows/release-secrets-check.yml` reports each secret as present without printing it.

| Secret | What it is | Backup |
|---|---|---|
| `DEVELOPER_ID_CERT_P12_BASE64` | The Developer ID Application certificate and private key, as a base64 `.p12` | 1Password |
| `DEVELOPER_ID_CERT_PASSWORD` | The `.p12`'s password | 1Password |
| `AC_API_KEY_P8_BASE64` | The App Store Connect API key's `.p8`, as base64. Apple only lets you download it once | 1Password |
| `AC_API_KEY_ID`, `AC_API_ISSUER_ID` | The API key's IDs | 1Password |
| `SPARKLE_ED_PRIVATE_KEY` | The EdDSA key that signs updates. See [Keys](updates.md#keys) | 1Password |
| `RELEASE_DEPLOY_KEY` | The private half of the deploy key that pushes release commits to `main` | 1Password |

`main`'s ruleset requires the merge gate's checks from everyone, admins included. Deploy keys are the only exception, and the release's should be the repository's only deploy key with write access. To replace it, add a new one, update the secret and remove the old one.

GitHub secrets can't be read back, so 1Password is the only way to restore them. Losing the certificate only means creating a new one under the same team, but losing the EdDSA key strands every installed copy.

The signing keychain isn't backed up, because each job creates its own with a random password and deletes it when it ends.

## Rolling back

Sparkle never downgrades, so rolling back means shipping a newer build with the problem reverted: revert on `main`, add a fragment saying what changed, and release. Don't delete a published Release, because appcast entries and later deltas link to it.
