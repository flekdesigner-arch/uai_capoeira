// lib/modules/sistema/atualizacoes/services/local_publish_runner_base.dart
//
// =====================================================
// 🚀 BASE DO EXECUTOR LOCAL DE PUBLICAÇÃO - UAI
// =====================================================
//
// Este arquivo é seguro para APK, PWA e Windows.
// Não usa dart:io.
// Não executa comandos.
// Ele define o contrato que o executor Windows vai seguir.
//
// A ideia da versão 64:
// - A tela chama um runner.
// - No Windows, o runner real executa PowerShell.
// - No PWA/APK, o runner indisponível bloqueia com mensagem segura.
// =====================================================

import 'package:flutter/foundation.dart';

import 'package:uai_capoeira/modules/sistema/atualizacoes/models/local_publish_automation_models.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/services/local_publish_platform_service.dart';

typedef LocalPublishStateCallback =
    void Function(LocalPublishAutomationState state);

typedef LocalPublishLogCallback = void Function(String line);

@immutable
class LocalPublishRunnerConfig {
  final String projectDir;
  final String scriptPath;
  final String version;
  final bool deployPwa;
  final bool buildApk;
  final bool deployFunctions;
  final bool stopOnError;

  const LocalPublishRunnerConfig({
    required this.projectDir,
    required this.scriptPath,
    required this.version,
    this.deployPwa = true,
    this.buildApk = true,
    this.deployFunctions = false,
    this.stopOnError = true,
  });

  String get expectedApkFileName => 'uai_capoeira_$version.apk';

  String get expectedApkPath {
    return '$projectDir\\build\\app\\outputs\\uai-apks\\$expectedApkFileName';
  }

  LocalPublishRunnerConfig copyWith({
    String? projectDir,
    String? scriptPath,
    String? version,
    bool? deployPwa,
    bool? buildApk,
    bool? deployFunctions,
    bool? stopOnError,
  }) {
    return LocalPublishRunnerConfig(
      projectDir: projectDir ?? this.projectDir,
      scriptPath: scriptPath ?? this.scriptPath,
      version: version ?? this.version,
      deployPwa: deployPwa ?? this.deployPwa,
      buildApk: buildApk ?? this.buildApk,
      deployFunctions: deployFunctions ?? this.deployFunctions,
      stopOnError: stopOnError ?? this.stopOnError,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'projectDir': projectDir,
      'scriptPath': scriptPath,
      'version': version,
      'deployPwa': deployPwa,
      'buildApk': buildApk,
      'deployFunctions': deployFunctions,
      'stopOnError': stopOnError,
      'expectedApkFileName': expectedApkFileName,
      'expectedApkPath': expectedApkPath,
    };
  }
}

@immutable
class LocalPublishRunnerResult {
  final bool success;
  final int exitCode;
  final String finalApkPath;
  final String output;
  final String errorOutput;
  final LocalPublishAutomationState state;

  const LocalPublishRunnerResult({
    required this.success,
    required this.exitCode,
    required this.finalApkPath,
    required this.output,
    required this.errorOutput,
    required this.state,
  });

  String get fullLog {
    final buffer = StringBuffer();

    if (output.trim().isNotEmpty) {
      buffer.writeln(output.trim());
    }

    if (errorOutput.trim().isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.writeln(errorOutput.trim());
    }

    return buffer.toString().trim();
  }
}

abstract class LocalPublishRunner {
  const LocalPublishRunner();

  LocalPublishPlatformInfo get platformInfo;

  bool get isAvailable => platformInfo.canRunLocalAutomation;

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
  Future<LocalPublishRunnerResult> run({
    required LocalPublishRunnerConfig config,
    LocalPublishStateCallback? onState,
    LocalPublishLogCallback? onLog,
  }) async {
    final message = platformInfo.blockedReason.isNotEmpty
        ? platformInfo.blockedReason
        : 'Automação local indisponível nesta plataforma.';

    final state =
        LocalPublishAutomationState.initial(
          available: false,
          platformLabel: platformInfo.platformLabel,
        ).copyWith(
          running: false,
          errorMessage: message,
          finishedAt: DateTime.now(),
        );

    onLog?.call(message);
    onState?.call(state);

    return LocalPublishRunnerResult(
      success: false,
      exitCode: -1,
      finalApkPath: '',
      output: '',
      errorOutput: message,
      state: state,
    );
  }
}
