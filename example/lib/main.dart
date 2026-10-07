import 'package:patchkite/patchkite.dart';
import 'package:flutter/material.dart';

// Change this text, then run `patchkite release-flutter` to test an OTA update.
const bundleMessage = 'Hello from the Dart code bundled in the binary';

void main() {
  runApp(const PatchkiteApp(
    checkFrequency: CheckFrequency.onAppResume,
    child: MyApp(),
  ));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _status = '-';
  String _progress = '';
  LocalPackage? _running;

  @override
  void initState() {
    super.initState();
    Patchkite.getUpdateMetadata().then((p) => setState(() => _running = p));
  }

  Future<void> _sync() async {
    try {
      await Patchkite.sync(
        options: const SyncOptions(installMode: InstallMode.immediate),
        onStatus: (s) => setState(() => _status = s.name),
        onProgress: (p) => setState(() => _progress = '${p.receivedBytes}/${p.totalBytes} bytes'),
      );
    } catch (e) {
      setState(() => _status = 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Patchkite Flutter Example')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(bundleMessage, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text('Running: ${_running == null ? 'binary' : '${_running!.label} (${_running!.packageHash.substring(0, 8)})'}'),
              Text('Status: $_status'),
              Text(_progress),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _sync, child: const Text('Sync now')),
              ElevatedButton(onPressed: () => Patchkite.restartApp(), child: const Text('Restart app')),
            ],
          ),
        ),
      ),
    );
  }
}
