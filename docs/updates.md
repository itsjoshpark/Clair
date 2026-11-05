# Updates

Clair updates itself with Sparkle 2, from `ClairUI`. It shows no Sparkle windows and has no update settings. The required behaviour is in the `software-updates` spec, and the reasoning is in design D4.

## How an update reaches a user

1. Sparkle checks `https://github.com/itsjoshpark/Clair/raw/main/.sparkle/appcast.xml` soon after the first launch, then every 24 hours. It asks no permission, because `package.sh` sets `SUEnableAutomaticChecks`, `SUAutomaticallyUpdate` and `SUScheduledCheckInterval` in `Info.plist`.
2. It downloads the delta for the running build if the appcast has one, and otherwise the full DMG, with no window. If a delta fails to apply, it downloads the full DMG.
3. Sparkle's `Autoupdate` tool checks the update's EdDSA signature against `SUPublicEDKey`, unpacks it, and waits for Clair to quit. An update that fails the check is dropped, and the menu doesn't change.
4. The Clair menu's "Check for Updates…" item now reads "Update Available…" with a "1 update" badge.
5. The update installs in one of three ways:
   - **Restart and Update**, from the item's alert
   - **Quitting**: `Autoupdate` replaces the app, and the next launch runs the new version
   - **Being away**: after 30 minutes without input, Clair relaunches on its own, unless a download is in progress, an incognito window is open, or a tab is audible or capturing. If something blocks it, it tries again after every further 30 minutes, and starts over once there's input.

Clair always reopens through Chromium's relaunch, never Sparkle's, so the app reopens once with its windows and tabs restored. It stays in the background if another app was active. Chromium's relauncher waits for `Autoupdate` to replace the app, for up to a minute (`patches/clair/update-relaunch-hook.patch`). If an install fails, the old version reopens.

A site with a "leave this page?" prompt can stop a relaunch, including an idle one. Its dialog stays open until someone answers it, and the update still installs on the next quit.

## Keys

The EdDSA key pair signs every update. `package.sh` writes its public half, `.sparkle/public-ed-key.txt`, into `Info.plist` as `SUPublicEDKey`.

- **Private key:** the `release` environment's `SPARKLE_ED_PRIVATE_KEY` secret, backed up in the owner's 1Password. It exists nowhere else.
- **If the key is lost:** installed copies can't take another update, so users would have to reinstall by hand. That's why the backup matters.
- **If the key leaks:** someone else could sign updates. Ship an update with a new public key at once, signed with the old key, and rotate the secret and the backup.

To check that the backup matches the committed key, import it into `generate_keys` from Sparkle's release tarball and compare what `generate_keys -p` prints with `.sparkle/public-ed-key.txt`.

### The test-only key

`tests/runtime/update-key/` holds a second key pair for local test appcasts and the quality checks. Its private half is committed on purpose. A package trusts it only when it's built with `--public-key tests/runtime/update-key/public-ed-key.txt`, and release packages never are.

## Rollback

Sparkle never installs a build number lower than the running one, so a release can't be withdrawn from those who already have it. To roll back, ship a newer build with the problem reverted.

## Testing against a local appcast

Everything below uses packages signed ad hoc. `package.sh` marks those as non-official, which is the only kind that reads these environment variables:

- `CLAIR_TEST_FEED_URL`: the appcast to use instead of `SUFeedURL`
- `CLAIR_TEST_UPDATE_IDLE_SECONDS`: the idle time to use instead of 30 minutes

The environment doesn't survive a relaunch, because Launch Services starts the new process. That doesn't matter here: the new version has nothing further to install.

Testing updates replaces the app in place, so work in a throwaway directory. Pass `--user-data-dir` and `--use-mock-keychain` so your own data and keychain aren't touched. Chromium keeps both flags across a relaunch.

The rest of Sparkle's state is outside those flags, under the real bundle ID: `~/Library/Preferences/dev.joshuapark.Clair.plist` and `~/Library/Caches/dev.joshuapark.Clair`. On a Mac where you also use a real Clair, test on another user account.

1. Download an engine, and package an old and a new version with the test key:

   ```sh
   work="$(mktemp -d)"
   gh release download "chromium-engine-$(scripts/engine-key.sh)" --pattern '*.zip' --dir "$work"
   engine="$(ls "$work"/*.zip)"
   key=tests/runtime/update-key/public-ed-key.txt
   ./package.sh --version 0.1.0 --build 100 --public-key "$key" "$engine" "$work/old"
   ./package.sh --version 0.1.1 --build 101 --public-key "$key" "$engine" "$work/new"
   ```

2. Make a test appcast offering the new version, and serve it:

   ```sh
   mkdir "$work/feed"
   cp "$work/new/Clair-0.1.1-arm64.dmg" "$work/feed/"
   scripts/make-test-appcast.sh --appcast "$work/feed/appcast.xml" \
     --dmg "$work/feed/Clair-0.1.1-arm64.dmg" --version 0.1.1 --build 101 \
     --base-url http://localhost:8123
   (cd "$work/feed" && python3 -m http.server 8123 --bind 127.0.0.1)
   ```

3. In another terminal, with `work` set again, start the old version:

   ```sh
   CLAIR_TEST_FEED_URL=http://localhost:8123/appcast.xml \
     "$work/old/Clair.app/Contents/MacOS/Clair" \
     --user-data-dir="$work/data" --use-mock-keychain --no-first-run
   ```

   Within a few seconds of a first launch, the server logs requests for the appcast and the DMG, and the Clair menu reads "Update Available…". If an earlier test has already checked, Sparkle waits out the 24 hours: choose "Check for Updates…" instead, or run `defaults delete dev.joshuapark.Clair SULastCheckTime` first.

4. Choose "Update Available…", then "Restart and Update". Clair reopens as 0.1.1, with the same windows and tabs.

To watch what Sparkle does:

```sh
log stream --level info --style compact \
  --predicate 'subsystem == "dev.joshuapark.Clair" OR subsystem == "org.sparkle-project.Sparkle"'
```

### Other cases

Reset between cases by quitting Clair, replacing `$work/old/Clair.app` with a fresh package, and removing `SULastCheckTime` as above.

| Case | Appcast | Expected |
|---|---|---|
| Install on quit | as above | Quit Clair: `$work/old/Clair.app` becomes 0.1.1, and nothing reopens |
| Install while idle | as above, with `CLAIR_TEST_UPDATE_IDLE_SECONDS=20` | With an update waiting and no input for 20 seconds, Clair relaunches as 0.1.1. If another app was active, Clair stays behind it |
| Up to date | `--build 100`, or lower | "Check for Updates…" says Clair is up to date |
| Check fails | stop the server | "Check for Updates…" says the check failed |
| Tampered update | serve a changed copy of the DMG under the same name, with the original's signature | Nothing is offered, the menu doesn't change, and Clair keeps running. `Autoupdate` logs the EdDSA failure |
| Newer macOS needed | `--minimum-system-version 99.0` | Nothing is offered, and a manual check says up to date |
| Delta | `--delta "100,$work/feed/100-101.delta"` (below) | The server logs only the delta, and the update installs |
| Delta that can't apply | a delta made from a different app than the running one | The server logs the delta, then the full DMG, and the update installs |

Make a delta with Sparkle's tool, which `fetch-sparkle.sh` puts in `build/sparkle/bin`:

```sh
build/sparkle/bin/BinaryDelta create "$work/old/Clair.app" "$work/new/Clair.app" "$work/feed/100-101.delta"
```

An ad hoc package logs that its code signature doesn't match the old version's. That's expected: Sparkle accepts the update because its EdDSA signature is valid.

Release builds follow the same rule. Sparkle accepts an update when either signature carries over:

- its EdDSA signature verifies against the running app's key, and the new app's code signature is valid, whatever its team
- the new app is signed by the same Developer ID team, and its EdDSA signature verifies against the new app's own key

So one release can move to a new Developer ID team or to a new EdDSA key, but not both (Sparkle's `SUUpdateValidator.m`). The EdDSA key is what tells Clair's updates apart. A different team's build signed with Clair's key would install, which is one more reason the private key must stay secret.
