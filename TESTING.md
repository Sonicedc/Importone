# Device acceptance checklist

Record device, iOS version, jailbreak version, loader, and Dopamine version for every run.

- Install the rootless deb; confirm the daemon runs as mobile and `/var/lib/ringtones` is owned by mobile with mode 0755.
- Open Settings → Importone: verify logo, switch default, light/dark credits images, author URL, repository URL, and license text.
- Enable/disable, then create a new Share Sheet in Files and Safari downloads. Verify the activity tracks the switch without a respring.
- Import MP3, WAV, AAC/M4A, and valid M4R samples under 40 seconds. Check stage text, blur, progress, rename, resulting name, and `.m4r` container.
- Verify ToneLibrary's `importTone:metadata:completionBlock:` on the target device: NSData payload, `Name` metadata key, completion with first argument `BOOL success` (confirmed by the iOS 16.2 runtime test). Adjust the isolated adapter in Daemon/main.m if the target ABI differs.
- Confirm registered tones appear in Settings, preview correctly, and play on a real incoming call after locking the device and after a userspace reboot/re-jailbreak.
- Rename with Unicode, whitespace, an empty name, slash, colon, control characters, and over 80 characters. Verify invalid names cause no writes outside the ringtone directory.
- Import an existing name twice, including simultaneously from two apps. Verify the original is never replaced.
- Try a WAV/MP3 renamed to M4R, corrupt audio, DRM audio, video, zero-byte input, zero/indefinite duration, 41-second audio, >100 MB input, and >10 MB M4R output. Verify clear errors and cleanup.
- Import from an iCloud-backed Files item to check coordinated reads and security-scoped access.
- Cancel rename and check temporary files are removed.
- Stop the daemon : verify a clear service-unavailable error.
- Disable while the rename prompt is shown: verify the service rejects the new request.
- Verify private-API failure never reports success; check registration timeout messaging and retry behavior.
- Uninstall: confirm daemon stops, settings disappear, and registered tones and user files remain.

Build/package verification on the development host does not substitute for these checks.

## Non-presenting on-device UI integration probe

`tests/UIProbe.m` is built separately from the package and verifies the activity accepts an audio URL, rejects a PDF, accepts an audio item provider, appears in a modern Share Sheet configuration, loads the actual Settings view, checks the 220-point rounded progress card, and verifies native custom-tone section rows and selection for seven alert types. It does not present UI or replace the visual acceptance checks above.

## Custom tone management

- In Importone preferences, swipe left or tap a custom tone to rename or remove it. Full swipe must not delete a tone. Confirm that removal requires confirmation.
- Rename a disposable imported tone; verify its native identifier stays the same and its name updates in the native picker. Reject duplicate names and unsafe paths.
- Remove the disposable tone; verify both its native registration and stored audio disappear, while other tones remain.
- Use Open Sounds & Haptics; verify the native settings controller opens with its ringtone and alert-tone links.
- Run the on-device UI probe to check actual preference rows, swipe configurations, and native shortcut loading.

## Assigned-tone deletion protection

- Create a disposable tone named `Importone Guard Check` and run `tests/ToneUsageProbe.m` on-device. The probe temporarily assigns that tone to each of the seven native sound categories, verifies the service rejects removal, then restores all original assignments in a finally block. It removes only the unassigned disposable tone after restoration.
- In Preferences, attempting removal of an assigned tone must show an error asking the user to select a replacement, without offering a delete confirmation. Confirm that unassigned tones still require confirmation.
- The service repeats the assignment check at deletion time to cover changes made while a confirmation is open.

## Waveform cropping

- Share audio longer than 40 seconds, including an existing .m4r. The crop sheet must open before naming the tone. Short audio keeps the direct import flow.
- Swipe the waveform to move a fixed 40-second range. Verify both ends stop at the source boundaries. Hold either bracket for an 8-second precision view, drag to fine-tune, and release to zoom out.
- Preview the selection; verify it stops at the end, stops when the selection moves, and stops on cancel or Use Selection.
- Run `tests/CropProbe.m` with synthetic long audio. It checks the actual long-file handoff, decoded peaks, both gesture mappings, muted preview, export range and decoded duration, rename handoff, and cancellation cleanup. Test WAV and .m4r at normal and low sample rates.
- AAC container duration can differ slightly from the decoded sample duration at low sample rates. Check decoded duration and keep the native asset duration within the service limit.
