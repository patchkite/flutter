# patchkite

Flutter SDK for [Patchkite](https://github.com/patchkite/patchkite): self-hosted over-the-air updates for your Dart code.

Patchkite replaces your app's compiled Dart code (`libapp.so`) with a newer version downloaded from your own server, so you can ship fixes without a store release.

- **Android only.** Apple doesn't allow loading new native code, so on iOS the plugin is a no-op that always reports "up to date" — you can keep one codebase.
- Diff updates and binary patches; automatic rollback; code signing.
- Updates only reach binaries built with the same Flutter engine revision.

## Install

```bash
flutter pub add patchkite
```

## Setup

`android/app/src/main/kotlin/.../MainActivity.kt`:

```kotlin
import io.github.patchkite.flutter.PatchkiteFlutterActivity

class MainActivity : PatchkiteFlutterActivity()   // or PatchkiteFlutterFragmentActivity
```

`android/app/src/main/AndroidManifest.xml`, inside `<application>`:

```xml
<meta-data android:name="PatchkiteServerUrl" android:value="https://patchkite.example.com" />
<meta-data android:name="PatchkiteDeploymentKey" android:value="DEPLOYMENT_KEY" />
```

Dart:

```dart
import 'package:patchkite/patchkite.dart';

void main() => runApp(const PatchkiteApp(
      checkFrequency: CheckFrequency.onAppResume,
      child: MyApp(),
    ));
```

Release updates with the [Patchkite CLI](https://github.com/patchkite/cli), using the same Flutter version as your store build:

```bash
patchkite release-flutter MyApp-Android android
```

Read the [Flutter guide](https://patchkite.github.io/docs/guides/flutter/) for limitations, deployment keys per flavor, code signing, and verification, and the [API reference](https://patchkite.github.io/docs/reference/flutter-api/) for everything else.

Make sure your use complies with Google Play's policy on downloading executable code.

## License

[MIT](LICENSE)
