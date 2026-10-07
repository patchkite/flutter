import 'dart:io';

import 'package:patchkite/patchkite.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding blocks HttpClient; the SDK needs to talk to the local fake server.
  HttpOverrides.global = null;

  late FakeServer server;
  late FakeNative native;

  setUp(() async {
    server = FakeServer();
    await server.start();
    native = FakeNative(server.url)..install();
    await Patchkite.configure(); // reset the configuration cache
  });

  tearDown(() => server.stop());

  const available = {
    'is_available': true,
    'is_mandatory': false,
    'update_app_version': false,
    'should_run_binary_version': false,
    'target_binary_range': '1.0.0',
    'download_url': 'http://example.invalid/pkg.zip',
    'package_hash': 'hash-v2',
    'label': 'v2',
    'package_size': 1234,
    'description': 'Bug fixes',
    'is_diff': true,
  };

  group('checkForUpdate', () {
    test('sends the version, local hash, and engine revision to the server', () async {
      native.responses['getUpdateMetadata'] = (_) => {'packageHash': 'hash-v1', 'label': 'v1'};
      await Patchkite.checkForUpdate();
      final q = server.requests.single.query;
      expect(q['deployment_key'], 'dep-key');
      expect(q['app_version'], '1.0.0');
      expect(q['package_hash'], 'hash-v1');
      expect(q['label'], 'v1');
      expect(q['engine_revision'], 'engine-abc');
      expect(q['client_unique_id'], 'client-1');
      expect(q['client_features'], 'bsdiff');
    });

    test('maps the update response to a RemotePackage', () async {
      server.updateInfo = available;
      final remote = await Patchkite.checkForUpdate();
      expect(remote, isNotNull);
      expect(remote!.label, 'v2');
      expect(remote.packageHash, 'hash-v2');
      expect(remote.packageSize, 1234);
      expect(remote.description, 'Bug fixes');
      expect(remote.isDiff, isTrue);
      expect(remote.failedInstall, isFalse);
    });

    test('returns null when the server package matches the installed one', () async {
      server.updateInfo = available;
      native.responses['getUpdateMetadata'] = (_) => {'packageHash': 'hash-v2', 'label': 'v2'};
      expect(await Patchkite.checkForUpdate(), isNull);
    });

    test('falls back to the binary when the server requests it', () async {
      server.updateInfo = {'is_available': false, 'should_run_binary_version': true};
      native.responses['getUpdateMetadata'] = (_) => {'packageHash': 'hash-v1', 'label': 'v1'};
      expect(await Patchkite.checkForUpdate(), isNull);
      expect(native.called('clearUpdates'), hasLength(1));
    });

    test('notifies when the update requires a newer binary', () async {
      server.updateInfo = {...available, 'update_app_version': true, 'target_binary_range': '2.0.0'};
      RemotePackage? mismatch;
      expect(await Patchkite.checkForUpdate(onBinaryVersionMismatch: (u) => mismatch = u), isNull);
      expect(mismatch?.appVersion, '2.0.0');
    });

    test('does not contact the server on unsupported platforms', () async {
      native.config = {'unsupported': true};
      await Patchkite.configure();
      expect(await Patchkite.checkForUpdate(), isNull);
      expect(server.requests, isEmpty);
    });

    test('wraps native errors in PatchkiteException', () async {
      native.responses['getUpdateMetadata'] = (_) => throw PlatformException(code: 'E', message: 'Package hash mismatch');
      await expectLater(
        Patchkite.getUpdateMetadata(),
        throwsA(isA<PatchkiteException>().having((e) => e.message, 'message', 'Package hash mismatch')),
      );
    });
  });

  group('sync', () {
    test('up to date', () async {
      final statuses = <SyncStatus>[];
      expect(await Patchkite.sync(onStatus: statuses.add), SyncStatus.upToDate);
      expect(statuses, [SyncStatus.checkingForUpdate, SyncStatus.upToDate]);
    });

    test('downloads, reports the download, and installs with the install mode', () async {
      server.updateInfo = available;
      native.responses['downloadUpdate'] = (call) => {...(call.arguments as Map), 'isPending': true};
      final statuses = <SyncStatus>[];
      final result = await Patchkite.sync(
        options: const SyncOptions(installMode: InstallMode.onNextRestart),
        onStatus: statuses.add,
      );
      expect(result, SyncStatus.updateInstalled);
      expect(statuses, [
        SyncStatus.checkingForUpdate,
        SyncStatus.downloadingPackage,
        SyncStatus.installingUpdate,
        SyncStatus.updateInstalled,
      ]);
      final download = native.called('downloadUpdate').single.arguments as Map;
      expect(download['downloadUrl'], available['download_url']);
      expect(download['isDiff'], isTrue);
      final install = native.called('installUpdate').single.arguments as Map;
      expect(install, {'packageHash': 'hash-v2', 'installMode': InstallMode.onNextRestart.index});
      expect(native.called('restartApp'), isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(server.posts('report_status/download').single['label'], 'v2');
    });

    test('mandatory updates use mandatoryInstallMode (default: restart immediately)', () async {
      server.updateInfo = {...available, 'is_mandatory': true};
      native.responses['downloadUpdate'] = (call) => {...(call.arguments as Map), 'isMandatory': true};
      await Patchkite.sync();
      expect((native.called('installUpdate').single.arguments as Map)['installMode'], InstallMode.immediate.index);
      expect(native.called('restartApp'), hasLength(1));
    });

    test('restart is deferred while disallowRestart is active', () async {
      server.updateInfo = {...available, 'is_mandatory': true};
      native.responses['downloadUpdate'] = (call) => {...(call.arguments as Map), 'isMandatory': true};
      Patchkite.disallowRestart();
      await Patchkite.sync();
      expect(native.called('restartApp'), isEmpty);
      Patchkite.allowRestart();
      await Future<void>.delayed(Duration.zero);
      expect(native.called('restartApp'), hasLength(1));
    });

    test('ignores updates that previously failed and were rolled back', () async {
      server.updateInfo = available;
      native.responses['isFailedUpdate'] = (_) => true;
      expect(await Patchkite.sync(), SyncStatus.upToDate);
      expect(native.called('downloadUpdate'), isEmpty);
    });

    test('a second sync while one is running returns immediately', () async {
      final first = Patchkite.sync();
      expect(await Patchkite.sync(), SyncStatus.syncInProgress);
      await first;
    });
  });
}
