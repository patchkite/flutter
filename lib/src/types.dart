/// Public enums and types.
library;

enum CheckFrequency { onAppStart, onAppResume, manual }

enum InstallMode {
  /// Restart the app as soon as the update is installed.
  immediate,

  /// Apply the update the next time the app is launched (default).
  onNextRestart,

  /// Apply the update when the app returns to the foreground after at least [SyncOptions.minimumBackgroundDuration].
  onNextResume,

  /// Apply the update once the app has been in the background for [SyncOptions.minimumBackgroundDuration].
  onNextSuspend,
}

enum SyncStatus {
  upToDate,
  updateInstalled,
  updateIgnored,
  unknownError,
  syncInProgress,
  checkingForUpdate,
  awaitingUserAction,
  downloadingPackage,
  installingUpdate,
}

enum UpdateState { running, pending, latest }

class DownloadProgress {
  const DownloadProgress(this.receivedBytes, this.totalBytes);
  final int receivedBytes;
  final int totalBytes;
}

class RollbackRetryOptions {
  const RollbackRetryOptions({this.delayInHours = 24, this.maxRetryAttempts = 1});
  final int delayInHours;
  final int maxRetryAttempts;
}

class UpdateDialog {
  const UpdateDialog({
    this.title = 'Update available',
    this.optionalUpdateMessage = 'An update is available. Would you like to install it?',
    this.mandatoryUpdateMessage = 'An update is available that must be installed.',
    this.optionalInstallButtonLabel = 'Install',
    this.optionalIgnoreButtonLabel = 'Ignore',
    this.mandatoryContinueButtonLabel = 'Continue',
    this.appendReleaseDescription = false,
    this.descriptionPrefix = ' Description: ',
  });
  final String title;
  final String optionalUpdateMessage;
  final String mandatoryUpdateMessage;
  final String optionalInstallButtonLabel;
  final String optionalIgnoreButtonLabel;
  final String mandatoryContinueButtonLabel;
  final bool appendReleaseDescription;
  final String descriptionPrefix;
}

class SyncOptions {
  const SyncOptions({
    this.deploymentKey,
    this.installMode = InstallMode.onNextRestart,
    this.mandatoryInstallMode = InstallMode.immediate,
    this.minimumBackgroundDuration = Duration.zero,
    this.updateDialog,
    this.rollbackRetryOptions,
    this.ignoreFailedUpdates = true,
  });
  final String? deploymentKey;
  final InstallMode installMode;
  final InstallMode mandatoryInstallMode;
  final Duration minimumBackgroundDuration;
  final UpdateDialog? updateDialog;
  final RollbackRetryOptions? rollbackRetryOptions;
  final bool ignoreFailedUpdates;
}

class PatchkiteConfiguration {
  PatchkiteConfiguration.fromMap(Map<dynamic, dynamic> m)
      : appVersion = m['appVersion'] as String? ?? '1.0.0',
        deploymentKey = m['deploymentKey'] as String?,
        serverUrl = m['serverUrl'] as String?,
        clientUniqueId = m['clientUniqueId'] as String? ?? '',
        engineRevision = m['engineRevision'] as String?,
        unsupported = m['unsupported'] == true;
  final String appVersion;
  final String? deploymentKey;
  final String? serverUrl;
  final String clientUniqueId;
  final String? engineRevision;

  /// true on platforms that do not support OTA updates yet (iOS).
  final bool unsupported;
}

/// Update metadata.
class PatchkitePackage {
  PatchkitePackage({
    required this.appVersion,
    required this.deploymentKey,
    required this.description,
    required this.isMandatory,
    required this.label,
    required this.packageHash,
    required this.packageSize,
    this.failedInstall = false,
    this.isFirstRun = false,
    this.isPending = false,
  });

  factory PatchkitePackage.fromMap(Map<dynamic, dynamic> m) => PatchkitePackage(
        appVersion: m['appVersion'] as String? ?? '',
        deploymentKey: m['deploymentKey'] as String? ?? '',
        description: m['description'] as String? ?? '',
        isMandatory: m['isMandatory'] == true,
        label: m['label'] as String? ?? '',
        packageHash: m['packageHash'] as String? ?? '',
        packageSize: (m['packageSize'] as num?)?.toInt() ?? 0,
        isPending: m['isPending'] == true,
      );

  final String appVersion;
  final String deploymentKey;
  final String description;
  final bool isMandatory;
  final String label;
  final String packageHash;
  final int packageSize;
  bool failedInstall;
  bool isFirstRun;
  bool isPending;

  Map<String, dynamic> toMap() => {
        'appVersion': appVersion,
        'deploymentKey': deploymentKey,
        'description': description,
        'isMandatory': isMandatory,
        'label': label,
        'packageHash': packageHash,
        'packageSize': packageSize,
      };

  @override
  String toString() => 'PatchkitePackage($label, $packageHash)';
}
