# Releasing Clair

A release runs from `main` through `.github/workflows/release.yml`, mostly on the owner's Mac. It works out the version, makes sure the commit has an engine and passing quality checks, packages and notarizes the app, and publishes it. `main` gets the appcast last, so no entry points at a file that doesn't exist yet.

## Before you start

- **Notes:** `.changes/unreleased/` needs at least one Changie fragment. User-facing pull requests add their own; see [`.changes/README.md`](../.changes/README.md).
- **Runner:** the owner's Mac must be online, with its runner started (`./run.sh`).
- **Certificate:** the Developer ID certificate expires on 2027-02-01. The release warns in the last 30 days and stops once it has expired.
- **Quality checks:** if `quality.yml` is still running for the commit after its merge, wait for it. Otherwise the release runs the whole suite again.
- **`main`:** merge nothing between the dry run you test and the release being published. The release ships `main` as it is when you start it, and stops if `main` moves before the Release is created.

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

If `publish` fails, see [If `publish` fails](#if-publish-fails).

## Manual release checklist

The quality checks can't cover these. Run them on a dry-run DMG of the commit you are about to release:

1. Start a dry run from `main` and wait for it to finish.
2. On a Mac or user account that has never run Clair, sign in to GitHub in Safari, open the dry run's page and download the `clair-<version>` artifact. To get a fresh account, add a standard user in System Settings > Users & Groups, and delete it afterwards. Use a browser, because the first item needs the quarantine flag it adds, and `gh run download` doesn't add it.
3. Unzip the artifact, open `Clair-<version>-arm64.dmg`, drag Clair to Applications and open it from there.

- [ ] The notarized DMG opens after only the standard downloaded-from-the-internet prompt
- [ ] A CRX installs through the extension MIME flag
- [ ] ungoogled-chromium's default settings are in place
- [ ] System Settings lists Clair as a default browser, and a link from another app opens in it
- [ ] Opening a page on the local network makes macOS ask for access, with the text "Clair uses your local network to access websites and devices on your network."

Then start the real release from the same commit.

## After publishing

- [ ] The GitHub Release for `v<version>` is published and marked latest. It has the DMG, a delta for each of up to three previous releases, and `Clair-<version>-SHA256SUMS.txt`. Its notes end with the version, build number, ungoogled-chromium tag and engine key.
- [ ] The checksums match: download the assets with `gh release download v<version> --dir <dir>`, then run `shasum -a 256 -c Clair-<version>-SHA256SUMS.txt` in that directory.
- [ ] `main` ends with `chore: release <version> (<build>) [skip ci]`, tagged `v<version>`, and its appcast entry's links resolve:

  ```sh
  curl -fsL https://github.com/itsjoshpark/Clair/raw/main/.sparkle/appcast.xml |
    grep -o 'url="[^"]*"' | cut -d'"' -f2 | xargs -n1 curl -fsIL -o /dev/null -w '%{http_code} %{url_effective}\n'
  ```

- [ ] The DMG from the Release opens on a clean Mac or user account, as in the checklist above.
- [ ] From the second release on, the update path works with Developer ID-signed builds. Do this on an account running the previous release: a delta downloads in the background, Restart and Update restores the session, quitting installs the update, and so do 30 idle minutes. Release packages ignore the test feed, so only a published release can test this.

## If `publish` fails

`publish` has no partial reruns. Its error says which case you're in:

| Error | State | What to do |
|---|---|---|
| "main moved during the release, so nothing was published" | Nothing left the Mac | Run the release again |
| "creating the GitHub Release failed" | The tag is pushed, and `main` is unchanged | Delete any draft (`gh release delete v<version> --yes`) and the tag (`git push origin :refs/tags/v<version>`), then run the release again |
| "the Release for v<version> is still a draft" | The Release has every asset, but `main` is unchanged | Publish it (`gh release edit v<version> --draft=false --latest`), then bring the release commit to `main` as below |
| "The Release is public, but installed copies won't be offered it" | The Release is public, but the appcast isn't on `main` | Bring the release commit to `main` as below |

Until the appcast entry is on `main`, installed copies aren't offered the release, but nothing points at a missing file. Only the deploy key can push past `main`'s ruleset.

If `main` is still the release commit's parent, fast-forward it with the deploy key from 1Password. That keeps the tag on `main`. `-F /dev/null` and `IdentityAgent=none` stop your own SSH config from offering your key instead, as happened in `0.1.0`'s publish:

```sh
key="$(mktemp)" && op read "op://Private/qcm7ew5s3zeapoxwfuaa34t4nq/clair-release-deploy-key" >"$key"
GIT_SSH_COMMAND="ssh -F /dev/null -o IdentitiesOnly=yes -o IdentityAgent=none -i $key" \
  git push git@github.com:itsjoshpark/Clair.git "$(git rev-parse v<version>^{commit}):refs/heads/main"
rm -f "$key"
```

The push should report "Bypassed rule violations". Otherwise, go through a pull request. Its head can't be the release commit itself: that commit's `[skip ci]` would keep the required checks from running. Cherry-pick it and drop `[skip ci]` from the message:

```sh
git fetch origin main && git fetch origin tag v<version>
git switch -c release/v<version> origin/main
git cherry-pick v<version>
git commit --amend -m "chore: release <version> (<build>)"
git push -u origin release/v<version>
gh pr create --title "chore: release <version> (<build>)" --body "Brings v<version>'s appcast entry to main."
```

Merge it once its checks pass. The tag stays on the original commit, which is what the Release was built from.

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
