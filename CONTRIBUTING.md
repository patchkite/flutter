# Contributing to the Patchkite Flutter SDK

Thanks for helping! Open an issue first for larger changes.

```bash
flutter pub get
flutter analyze && flutter test
cd example && flutter pub get && flutter build apk --config-only
cd android && ./gradlew :patchkite:testDebugUnitTest
```

Try changes end to end with the example app (a **release** build on Android) against a local server; see the [quickstart](https://patchkite.github.io/docs/start/quickstart/).

- The package hash, signature, diff, and bsdiff logic in `android/` must match the server exactly, as specified in the [package format reference](https://patchkite.github.io/docs/reference/package-format/). The Kotlin tests check it against `test/fixtures`, which are synced from server releases by `scripts/update-fixtures.sh`.
- Log lines start with `[Patchkite]`; the CLI's `debug` command filters on it.

## Releases

Maintainers bump `version` in `pubspec.yaml`, add a CHANGELOG entry, and push a `vX.Y.Z` tag. CI publishes to pub.dev with automated publishing.
