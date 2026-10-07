## 1.0.0

First public release.

- `Patchkite.sync`, `checkForUpdate`, `getUpdateMetadata`, `notifyAppReady`, `restartApp`, `clearUpdates`, and the `PatchkiteApp` widget.
- Android: loads updated `libapp.so` via `PatchkiteFlutterActivity` and `PatchkiteFlutterFragmentActivity`.
- Diff updates and bsdiff binary patches, automatic rollback, code signing (RS256), and install metrics reporting.
- iOS: no-op implementation with the same Dart API.
