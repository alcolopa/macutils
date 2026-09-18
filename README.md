# MacMonitor

A lightweight menu bar system monitor for macOS: CPU, memory, disk, network, battery, temperatures, displays and weather, each with its own widget and popover.

## Install

Download the latest `MacMonitor-<version>.zip` from [Releases](../../releases), unzip it and move `MacMonitor.app` to `/Applications`.
The build is ad-hoc signed, so on first launch right-click the app → **Open** (or allow it in System Settings → Privacy & Security).

Enable **Launch MacMonitor at login** in Preferences → General.

## Build from source

Requires macOS 13+ and Swift 6.

```sh
swift run MacMonitor          # run directly
./scripts/build_app.sh        # build MacMonitor.app + dist/MacMonitor-<version>.zip
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

If MacMonitor is useful to you, you can support development with USDT on the **Arbitrum One** network:

`0x157F29dF2DF3760A96D8AbeFF9c0c93004Eb0de0`

[View on Arbiscan](https://arbiscan.io/address/0x157F29dF2DF3760A96D8AbeFF9c0c93004Eb0de0)

Only send USDT on Arbitrum One to this address. Funds sent on other networks may be lost.
