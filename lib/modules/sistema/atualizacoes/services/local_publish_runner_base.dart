import 'package:flutter/foundation.dart';

import 'package:uai_capoeira/modules/sistema/atualizacoes/models/local_publish_automation_models.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/services/local_publish_platform_service.dart';

typedef LocalPublishStateCallback = void Function(LocalPublishAutomationState state);
typedef LocalPublishLogCallback = void Function(String line);

@immutable
class LocalProjectVersionPlan {
  final String currentVersion;
  final int currentBuild;
  final String nextVersion;
  final int nextBuild;

  const LocalProjectVersionPlan({
    required this.currentVersion,
    required this.currentBuild,
    required this.nextVersion,
    required this.nextBuild,
  });

  String get currentFullVersion => '$currentVersion+$currentBuild';
  String get nextFullVersion => '$nextVersion+$nextBuild';
}

@immutable
class LocalPublishRunnerConfig {
  final String projectDir;
  final String scriptPath;
  final String version;
  final int build;
  final bool deployPwa;
  final bool buildAndroid;
  final bool buildWindows;
  final bool skipPrepare;

  const LocalPublishRunnerConfig({
    required this.projectDir,
    required this.scriptPath,
    required this.version,
    required this.build,
    this.deployPwa = true,
    this.buildAndroid = true,
    this.buildWindows = true,
    this.skipPrepare = false,
  });

  String androidApkPath(String abi) =>
      '$projectDir\\build\\app\\outputs\\uai-apks\\$version\\uai_capoeira_${version}_$abi.apk';

  Map<String, String> get expectedAndroidApkPaths => {
        'armeabi-v7a': androidApkPath('armeabi-v7a'),
        'arm64-v8a': androidApkPath('arm64-v8a'),
        'x86_64': androidApkPath('x86_64'),
      };

  String get windowsInstallDir => r'C:\UAI Capoeira\app';
}

@immutable
class LocalPublishRunnerResult {
  final bool success;
  final int exitCode;
  final Map<String, String> androidApkPaths;
  final String windowsInstallDir;
  final String windowsPackagePath;
  final int windowsPackageSizeBytes;
  final int pwaBuildSizeBytes;
  final String output;
  final String errorOutput;
  final LocalPublishAutomationState state;

  const LocalPublishRunnerResult({
    required this.success,
    required this.exitCode,
    this.androidApkPaths = const {},
    this.windowsInstallDir = '',
    this.windowsPackagePath = '',
    this.windowsPackageSizeBytes = 0,
    this.pwaBuildSizeBytes = 0,
    required this.output,
    required this.errorOutput,
    required this.state,
  });

  String get finalApkPath => androidApkPaths['arm64-v8a'] ??
      (androidApkPaths.isEmpty ? '' : androidApkPaths.values.first);
}

abstract class LocalPublishRunner {
  const LocalPublishRunner();
  LocalPublishPlatformInfo get platformInfo;
  bool get isAvailable => platformInfo.canRunLocalAutomation;

  Future<LocalProjectVersionPlan?> readProjectVersionPlan({
    required String projectDir,
  });

  Future<LocalPublishRunnerResult> run({
    required LocalPublishRunnerConfig config,
    LocalPublishStateCallback? onState,
    LocalPublishLogCallback? onLog,
  });
}

class LocalPublishRunnerUnavailable extends LocalPublishRunner {
  final LocalPublishPlatformInfo _platformInfo;
  const LocalPublishRunnerUnavailable(this._platformInfo);
  @override
  LocalPublishPlatformInfo get platformInfo => _platformInfo;

  @override
  Future<LocalProjectVersionPlan?> readProjectVersionPlan({
    required String projectDir,
  }) async => null;

  @override
  Future<LocalPublishRunnerResult> run({
    required LocalPublishRunnerConfig config,
    LocalPublishStateCallback? onState,
    LocalPublishLogCallback? onLog,
  }) async {
    final message = platformInfo.blockedReason.isNotEmpty
        ? platformInfo.blockedReason
        : 'Automação local indisponível nesta plataforma.';
    final state = LocalPublishAutomationState.initial(
      available: false,
      platformLabel: platformInfo.platformLabel,
    ).copyWith(errorMessage: message, finishedAt: DateTime.now());
    onLog?.call(message);
    onState?.call(state);
    return LocalPublishRunnerResult(
      success: false,
      exitCode: -1,
      output: '',
      errorOutput: message,
      state: state,
    );
  }
}
