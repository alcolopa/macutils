# MacUtils

Small, sharp utilities for your Mac menu bar:

- **Clipboard manager:** hold **⌘⇧** and press **V** to open a picker in the middle of the screen, keep pressing **V** (or ↑/↓) to move through what you copied, and release to paste. **Esc** cancels. Needs Accessibility access (System Settings → Privacy & Security → Accessibility). History is kept in memory only (last 30 text copies) and password-manager copies are skipped.
- **Caffeinate:** click the cup in the menu bar to keep your Mac awake for 15 minutes up to 8 hours, or until you turn it off.
- **System monitor:** CPU, memory, disk, network, temperatures and weather, each with its own widget and popover.

## Install

1. Download the latest `MacUtils-<version>.zip` from [Releases](../../releases), unzip it and move `MacUtils.app` to `/Applications`.
2. Open it. macOS will likely say **"Apple could not verify "MacUtils" is free of malware"**. This is expected: MacUtils is open source and built by GitHub Actions from this repo, but it isn't signed with a paid Apple Developer ID or notarized, so Gatekeeper blocks every app downloaded this way. To allow it, do **one** of:
   - **Terminal (quickest):**
     ```sh
     xattr -dr com.apple.quarantine /Applications/MacUtils.app
     ```
     then open the app normally.
   - **System Settings:** open the app once (it will be blocked), go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to the MacUtils message, then confirm.

You only need to do this once per download. If you'd rather not trust a prebuilt binary, [build it from source](#build-from-source) instead. A local build isn't quarantined, so there's no warning.

If you're upgrading, quit the running MacUtils first (menu bar item → Quit). Otherwise opening the new copy just brings the old one forward.

Enable **Launch MacUtils at login** in Preferences → General.

## Build from source

Requires macOS 13+ and Swift 6.

```sh
swift run MacUtils          # run directly
./scripts/build_app.sh        # build MacUtils.app + dist/MacUtils-<version>.zip
./scripts/build_app.sh 1.2.0  # override the version
```

## Releasing

The version lives in `VERSION`. To publish a release:

```sh
echo "1.1.0" > VERSION
git commit -am "Release 1.1.0"
git tag v1.1.0 && git push origin main v1.1.0
```

Pushing a `v*` tag triggers `.github/workflows/release.yml`, which builds the app and attaches the zip to a GitHub release.

## Donate

If MacUtils is useful to you, you can support development with USDT on the **Arbitrum One** network:

`0x157F29dF2DF3760A96D8AbeFF9c0c93004Eb0de0`

[View on Arbiscan](https://arbiscan.io/address/0x157F29dF2DF3760A96D8AbeFF9c0c93004Eb0de0)

Only send USDT on Arbitrum One to this address. Funds sent on other networks may be lost.
