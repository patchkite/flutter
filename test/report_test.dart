import 'dart:io';

import 'package:patchkite/patchkite.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// Separate file: notifyAppReady only runs once per process (per test isolate).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('notifyAppReady reports the rollback and the running release', () async {
    final server = FakeServer();
    await server.start();
    final native = FakeNative(server.url)..install();
    final store = <String, String>{'lastReported': 'binary:1.0.0'};
    native.responses['popRollbackReport'] = (_) => {'label': 'v3', 'deploymentKey': 'dep-key'};
    native.responses['getUpdateMetadata'] = (_) => {'label': 'v2', 'deploymentKey': 'dep-key', 'packageHash': 'h2'};
    native.responses['getValue'] = (call) => store[(call.arguments as Map)['key']];
    native.responses['setValue'] = (call) {
      final args = call.arguments as Map;
      store[args['key'] as String] = args['value'] as String;
      return null;
    };

    await Patchkite.notifyAppReady();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(native.called('notifyApplicationReady'), hasLength(1));
    final reports = server.posts('report_status/deploy');
    expect(reports, hasLength(2));
    expect(reports[0], containsPair('status', 'DeploymentFailed'));
    expect(reports[0], containsPair('label', 'v3'));
    expect(reports[1], containsPair('status', 'DeploymentSucceeded'));
    expect(reports[1], containsPair('label', 'v2'));
    expect(reports[1], containsPair('previous_label_or_app_version', '1.0.0'));
    expect(reports[1].containsKey('previous_deployment_key'), isFalse);
    expect(store['lastReported'], 'dep-key:v2');
    await server.stop();
  });
}
