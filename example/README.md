# Patchkite Flutter example

Uses the `patchkite` plugin from the repository root.

Set `PatchkiteDeploymentKey` and `PatchkiteServerUrl` in `android/app/src/main/AndroidManifest.xml` (`10.0.2.2` is your machine from the Android emulator), then run a **release** build:

```bash
flutter run --release
```

Release an update from this folder with `patchkite release-flutter <app> android`.
