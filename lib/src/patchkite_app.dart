import 'package:flutter/widgets.dart';

import 'patchkite.dart';
import 'types.dart';

/// Equivalent of the `patchkite(options)(App)` HOC: wraps the root widget to sync automatically.
///
/// ```dart
/// runApp(const PatchkiteApp(
///   checkFrequency: CheckFrequency.onAppResume,
///   child: MyApp(),
/// ));
/// ```
class PatchkiteApp extends StatefulWidget {
  const PatchkiteApp({
    super.key,
    required this.child,
    this.checkFrequency = CheckFrequency.onAppStart,
    this.syncOptions = const SyncOptions(),
    this.onStatus,
    this.onProgress,
    this.onBinaryVersionMismatch,
  });

  final Widget child;
  final CheckFrequency checkFrequency;
  final SyncOptions syncOptions;
  final void Function(SyncStatus status)? onStatus;
  final void Function(DownloadProgress progress)? onProgress;
  final void Function(RemotePackage update)? onBinaryVersionMismatch;

  @override
  State<PatchkiteApp> createState() => _PatchkiteAppState();
}

class _PatchkiteAppState extends State<PatchkiteApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    if (widget.checkFrequency == CheckFrequency.manual) {
      Patchkite.notifyAppReady();
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  void _sync() {
    Patchkite.sync(
      options: widget.syncOptions,
      onStatus: widget.onStatus,
      onProgress: widget.onProgress,
      onBinaryVersionMismatch: widget.onBinaryVersionMismatch,
      context: widget.syncOptions.updateDialog != null && mounted ? context : null,
    ).catchError((_) => SyncStatus.unknownError);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.checkFrequency == CheckFrequency.onAppResume) _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
