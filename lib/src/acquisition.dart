import 'dart:convert';
import 'dart:io';

import 'types.dart';

/// Acquisition API client.
class AcquisitionClient {
  AcquisitionClient(this.config, this.deploymentKey);

  final PatchkiteConfiguration config;
  final String deploymentKey;
  static final HttpClient _http = HttpClient()..connectionTimeout = const Duration(seconds: 15);

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = config.serverUrl!.replaceAll(RegExp(r'/$'), '');
    return Uri.parse('$base/v1/public/$path').replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> updateCheck({required String appVersion, String? packageHash, String? label}) async {
    final req = await _http.getUrl(_uri('update_check', {
      'deployment_key': deploymentKey,
      'app_version': appVersion,
      'client_unique_id': config.clientUniqueId,
      // The Android plugin can apply binary patches (much smaller diffs for libapp.so).
      'client_features': 'bsdiff',
      'package_hash': ?packageHash,
      'label': ?label,
      if (config.engineRevision != null && config.engineRevision!.isNotEmpty) 'engine_revision': config.engineRevision!,
    }));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) throw HttpException('[Patchkite] update_check failed: ${res.statusCode} $body');
    return (jsonDecode(body) as Map<String, dynamic>)['update_info'] as Map<String, dynamic>;
  }

  Future<void> _post(String path, Map<String, dynamic> body) async {
    final req = await _http.postUrl(_uri(path));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({'client_unique_id': config.clientUniqueId, ...body}));
    final res = await req.close();
    await res.drain<void>();
    if (res.statusCode >= 300) throw HttpException('[Patchkite] $path failed: ${res.statusCode}');
  }

  Future<void> reportDeploy(Map<String, dynamic> body) =>
      _post('report_status/deploy', {'deployment_key': deploymentKey, ...body});

  Future<void> reportDownload(String label) =>
      _post('report_status/download', {'deployment_key': deploymentKey, 'label': label});
}
