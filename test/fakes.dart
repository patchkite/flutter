import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake acquisition server (local HTTP) that records requests from the SDK.
class FakeServer {
  late HttpServer _server;
  final requests = <({String path, Map<String, String> query, Map<String, dynamic>? body})>[];
  Map<String, dynamic> updateInfo = {'is_available': false};

  String get url => 'http://${_server.address.address}:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      final raw = await utf8.decoder.bind(req).join();
      final path = req.uri.path.replaceFirst('/v1/public/', '');
      requests.add((path: path, query: req.uri.queryParameters, body: raw.isEmpty ? null : jsonDecode(raw) as Map<String, dynamic>));
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(path == 'update_check' ? {'update_info': updateInfo} : {'ok': true}));
      await req.response.close();
    });
  }

  Future<void> stop() => _server.close(force: true);

  List<Map<String, dynamic>> posts(String path) => [
        for (final r in requests)
          if (r.path == path) r.body!,
      ];
}

/// Stand-in for the native plugin: per-method responses and a call log.
class FakeNative {
  FakeNative(this.serverUrl);

  final String serverUrl;
  final calls = <MethodCall>[];
  Map<String, Object?> config = {};
  final responses = <String, Object? Function(MethodCall call)>{};

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('patchkite'),
      (call) async {
        calls.add(call);
        final handler = responses[call.method];
        if (handler != null) return handler(call);
        if (call.method == 'getConfiguration') {
          return {
            'appVersion': '1.0.0',
            'deploymentKey': 'dep-key',
            'serverUrl': serverUrl,
            'clientUniqueId': 'client-1',
            'engineRevision': 'engine-abc',
            ...config,
          };
        }
        return null;
      },
    );
  }

  List<MethodCall> called(String method) => calls.where((c) => c.method == method).toList();
}
