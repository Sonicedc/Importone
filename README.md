# Importone

A rootless iOS jailbreak tweak that imports custom ringtones from the Share Sheet, entirely on-device.

![Importone logo](Preferences/Resources/icon@3x.png)

## Use

1. Install the package and dependencies, then respring or restart the app sharing the audio.
2. Open **Settings → Importone** and enable it (enabled by default).
3. Share a downloaded audio file from Files or an app that supplies a local file URL.
4. Tap **Importone**. Audio is checked, then converted to MPEG-4 audio with an `.m4r` extension if needed.
5. Rename it and tap **Import**. Select the registered tone in **Settings → Sounds & Haptics → Ringtone**.

The import sheet displays a blurred background, centered circular activity indicator, step text, and conversion progress. The credits match the supplied CarCanvas reference: Sonicedc, GitHub Repository, and Licenses. The GitHub button targets `https://github.com/Sonicedc/Importone`; the repository is public.

## Compatibility and boundaries

- Build target: iOS 15+, arm64/arm64e, Dopamine rootless (`iphoneos-arm64`). Installation targets iOS 16.2; end-to-end Share Sheet testing is still required.
- Requires a tweak loader (e.g. ElleKit), PreferenceLoader. The IPC bridge uses Dopamine’s read/write sandbox extension for `/var/jb/var/mobile`; RocketBootstrap is not required.
- One local audio file per import; ordinary web links, raw audio data, and item-provider-only share payloads are not currently supported.
- Source limit: 100 MB. Result limit: 10 MB. Maximum duration: 40 seconds. Longer audio is rejected without silently trimming it.
- AVFoundation-supported audio formats only; video and protected audio are rejected. An existing `.m4r` must contain MPEG-4 audio.
- Duplicate names are rejected; names cannot contain directory separators, colons, or control characters.
- Disable applies to new share sheets and new service requests. An import already submitted to iOS can finish.
- The service stores the named file in **`/var/lib/ringtones`**. `/Library/Ringtones` belongs to the sealed root on rootless installations. ToneLibrary creates its own registered copy and manifest; merely copying an `.m4r` does not make iOS list it.
- ToneLibrary is a private API. Its import payload, metadata, completion signature, and service permissions vary across iOS versions. The callback’s first parameter is a BOOL, confirmed on the target iOS 16.2 device. A successful build does not establish runtime compatibility. Missing API / Objective-C exceptions / reported import errors are surfaced to the user.
- Failed registrations remove the staging ringtone. Uninstallation preserves imported files and tones registered with iOS.
- The daemon runs as `mobile`, uses a binary-plist file queue in `/var/jb/var/mobile/Library/Importone/IPC`, and accepts bounded audio bytes and a validated basename rather than caller-selected filesystem paths. Any mobile-user process able to access the queue can request imports; this is not an authenticated per-app service.

## Build

Install Theos, an iOS SDK and signing/packaging tools. Set `THEOS` if it is not `$HOME/theos`.

```sh
./build.sh
```

The package is written to `packages/`. The SDK version is configured as 16.5 in `Makefile`. The build script keeps the compiler module cache in the project directory. Settings PNG assets are checked in; regenerate them with `python3 scripts/make_icon.py` (Pillow required).

The install script prepares `/var/lib/ringtones` for `mobile` and starts the launch daemon. The launch plist and maintainer scripts target the standard `/var/jb` rootless prefix; relocated jailbreak roots need launch-path adaptation before deployment.

## Device acceptance checks

Before a release, run the checklist in [TESTING.md](TESTING.md). In particular, verify the private ToneLibrary adapter and an incoming call using the imported tone. No production compatibility claim is made until those checks pass.

## GitHub

[Public source repository](https://github.com/Sonicedc/Importone).

```sh
git clone https://github.com/Sonicedc/Importone.git
cd Importone
./build.sh
```

## Credits

[Sonicedc](https://github.com/Sonicedc). Credit-row design and assets use the supplied CarCanvasSource reference. Third-party license notices are included in Settings → Importone → Licenses. Source license: all rights reserved pending an explicit license choice.
