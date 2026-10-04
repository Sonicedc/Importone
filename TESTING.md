# Device acceptance checklist

Record device, iOS version, jailbreak version, loader, and RocketBootstrap version for every run.

- Install the rootless deb; confirm the daemon runs as mobile and `/var/lib/ringtones` is owned by mobile with mode 0755.
- Open Settings → Importone: verify logo, switch default, light/dark credits images, author URL, repository URL, and license text.
- Enable/disable, then create a new Share Sheet in Files and Safari downloads. Verify the activity tracks the switch without a respring.
- Import MP3, WAV, AAC/M4A, and valid M4R samples under 40 seconds. Check stage text, blur, progress, rename, resulting name, and `.m4r` container.
- Verify ToneLibrary's `importTone:metadata:completionBlock:` on the target device: NSData payload, `name` metadata key, completion `(NSString *identifier, NSError *error)`. Adjust the isolated adapter in Daemon/main.m if the target ABI differs.
- Confirm registered tones appear in Settings, preview correctly, and play on a real incoming call after locking the device and after a userspace reboot/re-jailbreak.
- Rename with Unicode, whitespace, an empty name, slash, colon, control characters, and over 80 characters. Verify invalid names cause no writes outside the ringtone directory.
- Import an existing name twice, including simultaneously from two apps. Verify the original is never replaced.
- Try a WAV/MP3 renamed to M4R, corrupt audio, DRM audio, video, zero-byte input, zero/indefinite duration, 41-second audio, >100 MB input, and >10 MB M4R output. Verify clear errors and cleanup.
- Import from an iCloud-backed Files item to check coordinated reads and security-scoped access.
- Cancel rename and check temporary files are removed.
- Stop the daemon or remove RocketBootstrap: verify a clear service-unavailable error.
- Disable while the rename prompt is shown: verify the service rejects the new request.
- Verify private-API failure never reports success; check registration timeout messaging and retry behavior.
- Uninstall: confirm daemon stops, settings disappear, and registered tones and user files remain.

Build/package verification on the development host does not substitute for these checks.
