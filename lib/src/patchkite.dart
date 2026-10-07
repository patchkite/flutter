import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'acquisition.dart';
import 'types.dart';

void _log(String msg) => debugPrint('[Patchkite] $msg');

/// Error raised by Patchkite (download, hash/signature verification, installation).
class PatchkiteException implements Exception {
  PatchkiteException(this.message);
  final String message;
  @override
  String toString() => '[Patchkite] $message';
}

/// An update available on the server (equivalent of `RemotePackage`).
class RemotePackage extends PatchkitePackage {
  RemotePackage._({
    required super.appVersion,
    required super.deploymentKey,
    required super.description,
    required super.isMandatory,
    required super.label,
    required super.packageHash,
    required super.packageSize,
    required this.downloadUrl,
    required this.isDiff,
    required PatchkiteConfiguration config,
    super.failedInstall,
  }) : _config = config;

  final String downloadUrl;
  final bool isDiff;
  final PatchkiteConfiguration _config;

  /// Downloads and verifies the package (hash + signature).
  Future<LocalPackage> download([void Function(DownloadProgress)? onProgress]) async {
    StreamSubscription<dynamic>? sub;
    if (onProgress != null) {
      sub = Patchkite._progress.receiveBroadcastStream().listen((e) {
        final m = e as Map<dynamic, dynamic>;
        onProgress(DownloadProgress((m['receivedBytes'] as num).toInt(), (m['totalBytes'] as num).toInt()));
      });
    }
    try {
      final raw = await Patchkite._invoke<Map<dynamic, dynamic>>('downloadUpdate', {
        ...toMap(),
        'appVersion': _config.appVersion,
        'downloadUrl': downloadUrl,
        'isDiff': isDiff,
      });
      unawaited(AcquisitionClient(_config, deploymentKey).reportDownload(label).catchError((_) {}));
      return await LocalPackage._fromMap(raw!);
    } finally {
      await sub?.cancel();
    }
  }
}

/// An update already on the device (equivalent of `LocalPackage`).
class LocalPackage extends PatchkitePackage {
  LocalPackage._(PatchkitePackage p)
      : super(
          appVersion: p.appVersion,
          deploymentKey: p.deploymentKey,
          description: p.description,
          isMandatory: p.isMandatory,
          label: p.label,
          packageHash: p.packageHash,
          packageSize: p.packageSize,
          isPending: p.isPending,
        );

  static Future<LocalPackage> _fromMap(Map<dynamic, dynamic> m) async {
    final pkg = LocalPackage._(PatchkitePackage.fromMap(m));
    pkg.isFirstRun = await Patchkite._invoke<bool>('isFirstRun', {'packageHash': pkg.packageHash}) ?? false;
    pkg.failedInstall = await Patchkite._invoke<bool>('isFailedUpdate', {'packageHash': pkg.packageHash}) ?? false;
    return pkg;
  }

  Future<void> install({
    InstallMode installMode = InstallMode.onNextRestart,
    Duration minimumBackgroundDuration = Duration.zero,
  }) =>
      Patchkite._install(packageHash, installMode, minimumBackgroundDuration);
}

/// Main API.
class Patchkite {
  Patchkite._();

  static const MethodChannel _channel = MethodChannel('patchkite');
  static const EventChannel _progress = EventChannel('patchkite/progress');

  static PatchkiteConfiguration? _config;
  static bool _syncInProgress = false;
  static bool _restartAllowed = true;
  static bool _restartQueued = false;
  static Future<void>? _notifyReady;
  static _LifecycleInstaller? _lifecycleInstaller;

  static Future<T?> _invoke<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw PatchkiteException(e.message ?? e.code);
    }
  }

  /// Overrides the native configuration (optional; defaults come from strings.xml / AndroidManifest meta-data).
  static Future<void> configure({String? deploymentKey, String? serverUrl}) async {
    await _invoke<void>('configure', {'deploymentKey': deploymentKey, 'serverUrl': serverUrl});
    _config = null;
  }

  static Future<PatchkiteConfiguration> getConfiguration() async {
    return _config ??= PatchkiteConfiguration.fromMap((await _invoke<Map<dynamic, dynamic>>('getConfiguration'))!);
  }

  // ---------------------------------------------------------------- restart

  static void allowRestart() {
    _restartAllowed = true;
    if (_restartQueued) {
      _restartQueued = false;
      restartApp();
    }
  }

  static void disallowRestart() => _restartAllowed = false;
  static void clearPendingRestart() => _restartQueued = false;

  /// Restarts the app. In Flutter, AOT Dart code can only be replaced by restarting the process.
  static Future<void> restartApp({bool onlyIfUpdateIsPending = false}) async {
    if (onlyIfUpdateIsPending && await getUpdateMetadata(UpdateState.pending) == null) return;
    if (!_restartAllowed) {
      _restartQueued = true;
      return;
    }
    await _invoke<void>('restartApp');
  }

  static Future<void> _install(String hash, InstallMode mode, Duration minBackground) async {
    await _invoke<void>('installUpdate', {'packageHash': hash, 'installMode': mode.index});
    _lifecycleInstaller?.dispose();
    _lifecycleInstaller = null;
    switch (mode) {
      case InstallMode.immediate:
        await restartApp();
      case InstallMode.onNextResume:
      case InstallMode.onNextSuspend:
        _lifecycleInstaller = _LifecycleInstaller(mode, minBackground);
      case InstallMode.onNextRestart:
        break;
    }
  }

  // ---------------------------------------------------------------- metadata

  static Future<LocalPackage?> getUpdateMetadata([UpdateState state = UpdateState.running]) async {
    final raw = await _invoke<Map<dynamic, dynamic>>('getUpdateMetadata', {'updateState': state.index});
    return raw == null ? null : LocalPackage._fromMap(raw);
  }

  static Future<void> clearUpdates() => _invoke<void>('clearUpdates');

  // ---------------------------------------------------------------- check

  static Future<RemotePackage?> checkForUpdate({
    String? deploymentKey,
    void Function(RemotePackage update)? onBinaryVersionMismatch,
  }) async {
    final config = await getConfiguration();
    if (config.unsupported) {
      _log('OTA updates are not supported on this platform yet.');
      return null;
    }
    final key = deploymentKey ?? config.deploymentKey;
    if (key == null || key.isEmpty) throw StateError('[Patchkite] Deployment key is not set.');
    if (config.serverUrl == null) throw StateError('[Patchkite] Server URL is not set.');

    final local = await getUpdateMetadata(UpdateState.latest);
    final client = AcquisitionClient(config, key);
    final info = await client.updateCheck(
      appVersion: config.appVersion,
      packageHash: local?.packageHash,
      label: local?.label,
    );

    if (info['should_run_binary_version'] == true && local != null) {
      _log('Server requested a rollback to the binary version.');
      await clearUpdates();
      return null;
    }
    RemotePackage build(bool failed) => RemotePackage._(
          appVersion: info['target_binary_range'] as String? ?? config.appVersion,
          deploymentKey: key,
          description: info['description'] as String? ?? '',
          isMandatory: info['is_mandatory'] == true,
          label: info['label'] as String? ?? '',
          packageHash: info['package_hash'] as String? ?? '',
          packageSize: (info['package_size'] as num?)?.toInt() ?? 0,
          downloadUrl: info['download_url'] as String? ?? '',
          isDiff: info['is_diff'] == true,
          config: config,
          failedInstall: failed,
        );

    if (info['is_available'] != true || info['update_app_version'] == true || info['package_hash'] == local?.packageHash) {
      if (info['update_app_version'] == true) {
        _log('An update is available for binary ${info['target_binary_range']}, but this binary is ${config.appVersion}.');
        onBinaryVersionMismatch?.call(build(false));
      }
      return null;
    }
    final failed = await _invoke<bool>('isFailedUpdate', {'packageHash': info['package_hash']}) ?? false;
    return build(failed);
  }

  // ---------------------------------------------------------------- report

  static Future<void> _reportStatus() async {
    final config = await getConfiguration();
    if (config.unsupported || config.serverUrl == null) return;

    final rollback = await _invoke<Map<dynamic, dynamic>>('popRollbackReport');
    if (rollback != null) {
      _log('Update ${rollback['label']} failed and was rolled back.');
      await AcquisitionClient(config, rollback['deploymentKey'] as String)
          .reportDeploy({'app_version': config.appVersion, 'label': rollback['label'], 'status': 'DeploymentFailed'})
          .catchError((_) {});
    }

    final running = await _invoke<Map<dynamic, dynamic>>('getUpdateMetadata', {'updateState': UpdateState.running.index});
    final id = running != null ? '${running['deploymentKey']}:${running['label']}' : 'binary:${config.appVersion}';
    final last = await _invoke<String>('getValue', {'key': 'lastReported'});
    if (id == last) return;

    String? prevKey;
    String? prevLabel;
    if (last != null) {
      final i = last.indexOf(':');
      final k = last.substring(0, i);
      prevLabel = last.substring(i + 1);
      if (k != 'binary') prevKey = k;
    }
    final key = (running?['deploymentKey'] as String?) ?? config.deploymentKey;
    if (key == null) return;
    try {
      await AcquisitionClient(config, key).reportDeploy({
        'app_version': config.appVersion,
        if (running != null) 'label': running['label'],
        if (running != null) 'status': 'DeploymentSucceeded',
        'previous_label_or_app_version': ?prevLabel,
        'previous_deployment_key': ?prevKey,
      });
      await _invoke<void>('setValue', {'key': 'lastReported', 'value': id});
    } catch (_) {}
  }

  /// Marks the update as successfully running (prevents auto-rollback).
  static Future<void> notifyAppReady() => _notifyReady ??= () async {
        await _invoke<void>('notifyApplicationReady');
        unawaited(_reportStatus().catchError((_) {}));
      }();

  // ---------------------------------------------------------------- sync

  static Future<bool> _shouldIgnore(RemotePackage remote, SyncOptions options) async {
    if (!remote.failedInstall || !options.ignoreFailedUpdates) return false;
    final retry = options.rollbackRetryOptions;
    if (retry == null) return true;
    final raw = await _invoke<String>('getValue', {'key': 'latestRollbackInfo'});
    final info = raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (info == null || info['packageHash'] != remote.packageHash) {
      await _invoke<void>('setValue', {
        'key': 'latestRollbackInfo',
        'value': jsonEncode({'packageHash': remote.packageHash, 'time': now, 'count': 0}),
      });
      return true;
    }
    final hours = (now - (info['time'] as int)) / 3600000;
    final count = info['count'] as int;
    if (hours >= retry.delayInHours && count < retry.maxRetryAttempts) {
      await _invoke<void>('setValue', {
        'key': 'latestRollbackInfo',
        'value': jsonEncode({...info, 'time': now, 'count': count + 1}),
      });
      return false;
    }
    return true;
  }

  /// Checks for, downloads, and installs an update in a single call (equivalent of `patchkite.sync`).
  ///
  /// [context] is only required when [SyncOptions.updateDialog] is set.
  static Future<SyncStatus> sync({
    SyncOptions options = const SyncOptions(),
    void Function(SyncStatus status)? onStatus,
    void Function(DownloadProgress progress)? onProgress,
    void Function(RemotePackage update)? onBinaryVersionMismatch,
    BuildContext? context,
  }) async {
    final report = onStatus ?? _defaultStatusLogger;
    if (_syncInProgress) {
      report(SyncStatus.syncInProgress);
      return SyncStatus.syncInProgress;
    }
    _syncInProgress = true;
    try {
      await notifyAppReady();
      report(SyncStatus.checkingForUpdate);
      final remote = await checkForUpdate(deploymentKey: options.deploymentKey, onBinaryVersionMismatch: onBinaryVersionMismatch);

      if (remote == null || await _shouldIgnore(remote, options)) {
        if (remote != null) _log('This update previously failed and was rolled back; ignoring it.');
        final current = await getUpdateMetadata(UpdateState.latest);
        final status = current?.isPending == true ? SyncStatus.updateInstalled : SyncStatus.upToDate;
        report(status);
        return status;
      }

      final dialog = options.updateDialog;
      if (dialog != null && context != null && context.mounted) {
        report(SyncStatus.awaitingUserAction);
        final accepted = await _showDialog(context, dialog, remote);
        if (!accepted) {
          report(SyncStatus.updateIgnored);
          return SyncStatus.updateIgnored;
        }
      }

      report(SyncStatus.downloadingPackage);
      final local = await remote.download(onProgress);
      report(SyncStatus.installingUpdate);
      final mode = local.isMandatory ? options.mandatoryInstallMode : options.installMode;
      report(SyncStatus.updateInstalled);
      await local.install(installMode: mode, minimumBackgroundDuration: options.minimumBackgroundDuration);
      return SyncStatus.updateInstalled;
    } catch (e) {
      report(SyncStatus.unknownError);
      _log('$e');
      rethrow;
    } finally {
      _syncInProgress = false;
    }
  }

  static void _defaultStatusLogger(SyncStatus s) {
    const messages = {
      SyncStatus.checkingForUpdate: 'Checking for update.',
      SyncStatus.awaitingUserAction: 'Awaiting user action.',
      SyncStatus.downloadingPackage: 'Downloading package.',
      SyncStatus.installingUpdate: 'Installing update.',
      SyncStatus.upToDate: 'App is up to date.',
      SyncStatus.updateIgnored: 'User cancelled the update.',
      SyncStatus.updateInstalled: 'Update is installed and will be run on the next app restart.',
      SyncStatus.unknownError: 'An unknown error occurred.',
      SyncStatus.syncInProgress: 'Sync already in progress.',
    };
    final m = messages[s];
    if (m != null) _log(m);
  }

  static Future<bool> _showDialog(BuildContext context, UpdateDialog d, RemotePackage remote) async {
    var message = remote.isMandatory ? d.mandatoryUpdateMessage : d.optionalUpdateMessage;
    if (d.appendReleaseDescription && remote.description.isNotEmpty) message += '${d.descriptionPrefix}${remote.description}';
    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      pageBuilder: (ctx, _, _) => _PatchkiteDialog(
        title: d.title,
        message: message,
        actions: [
          if (!remote.isMandatory) (d.optionalIgnoreButtonLabel, false),
          (remote.isMandatory ? d.mandatoryContinueButtonLabel : d.optionalInstallButtonLabel, true),
        ],
      ),
    );
    return result ?? false;
  }
}

/// Minimal dialog without a Material/Cupertino dependency.
class _PatchkiteDialog extends StatelessWidget {
  const _PatchkiteDialog({required this.title, required this.message, required this.actions});
  final String title;
  final String message;
  final List<(String, bool)> actions;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(12)),
        child: DefaultTextStyle(
          style: const TextStyle(color: Color(0xFF111111), fontSize: 15, decoration: TextDecoration.none),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Text(message),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (final (label, value) in actions)
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(value),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Text(label, style: const TextStyle(color: Color(0xFF1565C0), fontWeight: FontWeight.w600)),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Handles InstallMode.onNextResume / onNextSuspend.
class _LifecycleInstaller with WidgetsBindingObserver {
  _LifecycleInstaller(this.mode, this.minBackground) {
    WidgetsBinding.instance.addObserver(this);
  }
  final InstallMode mode;
  final Duration minBackground;
  DateTime? _backgroundAt;
  Timer? _timer;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _backgroundAt = DateTime.now();
      if (mode == InstallMode.onNextSuspend) {
        _timer = Timer(minBackground, () => Patchkite.restartApp(onlyIfUpdateIsPending: true));
      }
    } else if (state == AppLifecycleState.resumed) {
      _timer?.cancel();
      final at = _backgroundAt;
      if (at != null && DateTime.now().difference(at) >= minBackground) {
        Patchkite.restartApp(onlyIfUpdateIsPending: true);
      }
      _backgroundAt = null;
    }
  }

  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}
