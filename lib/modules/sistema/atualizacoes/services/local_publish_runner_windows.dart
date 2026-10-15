import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uai_capoeira/modules/sistema/atualizacoes/models/local_publish_automation_models.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/services/local_publish_platform_service.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/services/local_publish_runner_base.dart';

class LocalPublishRunnerWindows extends LocalPublishRunner {
  final LocalPublishPlatformInfo _platformInfo;

  LocalPublishRunnerWindows({LocalPublishPlatformInfo? platformInfo})
      : _platformInfo = platformInfo ?? const LocalPublishPlatformService().getInfo();

  @override
  LocalPublishPlatformInfo get platformInfo => _platformInfo;

  @override
  Future<LocalProjectVersionPlan?> readProjectVersionPlan({
    required String projectDir,
  }) async {
    final pubspec = File('$projectDir\\pubspec.yaml');
    if (!pubspec.existsSync()) return null;

    final content = await pubspec.readAsString();
    final match = RegExp(
      r'^version:\s*([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+)\s*$',
      multiLine: true,
    ).firstMatch(content);

    if (match == null) return null;

    final major = int.tryParse(match.group(1) ?? '');
    final minor = int.tryParse(match.group(2) ?? '');
    final patch = int.tryParse(match.group(3) ?? '');
    final build = int.tryParse(match.group(4) ?? '');
    if (major == null || minor == null || patch == null || build == null) {
      return null;
    }

    return LocalProjectVersionPlan(
      currentVersion: '$major.$minor.$patch',
      currentBuild: build,
      nextVersion: '$major.$minor.${patch + 1}',
      nextBuild: build + 1,
    );
  }

  @override
  Future<LocalPublishRunnerResult> run({
    required LocalPublishRunnerConfig config,
    LocalPublishStateCallback? onState,
    LocalPublishLogCallback? onLog,
  }) async {
    var state = LocalPublishAutomationState.initial(
      available: platformInfo.canRunLocalAutomation,
      platformLabel: platformInfo.platformLabel,
    ).copyWith(running: true, startedAt: DateTime.now(), clearError: true, clearFinalApkPath: true);

    void emit() => onState?.call(state);
    void log(String value) { if (value.trim().isNotEmpty) onLog?.call(value); }
    void setStep(String id, LocalPublishStepStatus status, [String? detail]) {
      state = state.updateStep(stepId: id, status: status, log: detail);
      emit();
    }

    emit();
    if (!platformInfo.canRunLocalAutomation) {
      final message = platformInfo.blockedReason;
      state = state.copyWith(running: false, errorMessage: message, finishedAt: DateTime.now());
      emit();
      return LocalPublishRunnerResult(success: false, exitCode: -1, output: '', errorOutput: message, state: state);
    }

    if (!Directory(config.projectDir).existsSync()) {
      final message = 'Pasta do projeto não encontrada: ${config.projectDir}';
      state = state.copyWith(running: false, errorMessage: message, finishedAt: DateTime.now());
      emit();
      return LocalPublishRunnerResult(success: false, exitCode: -1, output: '', errorOutput: message, state: state);
    }
    if (!File(config.scriptPath).existsSync()) {
      final message = 'Script não encontrado: ${config.scriptPath}';
      state = state.copyWith(running: false, errorMessage: message, finishedAt: DateTime.now());
      emit();
      return LocalPublishRunnerResult(success: false, exitCode: -1, output: '', errorOutput: message, state: state);
    }

    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    final artifacts = <String, String>{};
    String windowsInstallDir = '';
    String windowsPackagePath = '';
    int windowsPackageSizeBytes = 0;
    int pwaBuildSizeBytes = 0;

    try {
      log('🚀 Release UAI ${config.version}+${config.build}');
      final args = <String>[
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', config.scriptPath,
        '-Auto', '-Version', config.version, '-Build', '${config.build}',
        if (!config.deployPwa) '-SkipPwa',
        if (!config.buildAndroid) '-SkipAndroid',
        if (!config.buildWindows) '-SkipWindows',
        if (config.skipPrepare) '-SkipPrepare',
      ];
      final process = await Process.start('powershell.exe', args, workingDirectory: config.projectDir, runInShell: false);

      Future<void> consume(Stream<List<int>> stream, StringBuffer buffer, {required bool stderr}) async {
        await for (final line in stream.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter())) {
          buffer.writeln(line);
          log(line);
          if (stderr) continue;
          if (line.startsWith('[UAI_STEP]|')) {
            final parts = line.split('|');
            if (parts.length >= 4) {
              final status = switch (parts[2]) {
                'running' => LocalPublishStepStatus.running,
                'success' => LocalPublishStepStatus.success,
                'error' => LocalPublishStepStatus.error,
                'skipped' => LocalPublishStepStatus.skipped,
                _ => LocalPublishStepStatus.pending,
              };
              setStep(parts[1], status, parts.sublist(3).join('|'));
            }
          } else if (line.startsWith('[UAI_ARTIFACT]|')) {
            final parts = line.split('|');
            if (parts.length >= 5 && parts[1] == 'android') {
              artifacts[parts[2]] = parts[3];
            } else if (parts.length >= 5 && parts[1] == 'windows') {
              if (parts[2] == 'install') {
                windowsInstallDir = parts[3];
              } else if (parts[2] == 'package') {
                windowsPackagePath = parts[3];
                windowsPackageSizeBytes = int.tryParse(parts[4]) ?? 0;
              }
            } else if (parts.length >= 5 && parts[1] == 'pwa') {
              pwaBuildSizeBytes = int.tryParse(parts[4]) ?? 0;
            }
          }
        }
      }

      final outFuture = consume(process.stdout, stdoutBuffer, stderr: false);
      final errFuture = consume(process.stderr, stderrBuffer, stderr: true);
      final exitCode = await process.exitCode;
      await Future.wait([outFuture, errFuture]);

      final expected = config.expectedAndroidApkPaths;
      for (final entry in expected.entries) {
        if (File(entry.value).existsSync()) artifacts[entry.key] = entry.value;
      }
      final allApksOk = !config.buildAndroid || expected.keys.every(artifacts.containsKey);
      final success = exitCode == 0 && allApksOk;

      if (success) {
        state = state.copyWith(
          running: false,
          finalApkPath: artifacts['arm64-v8a'] ?? '',
          finishedAt: DateTime.now(),
          clearError: true,
        );
      } else {
        final message = exitCode != 0
            ? 'Pipeline Windows falhou com código $exitCode.'
            : 'Pipeline terminou, mas nem todos os APKs por arquitetura foram localizados.';
        state = state.copyWith(running: false, errorMessage: message, finishedAt: DateTime.now());
      }
      emit();
      return LocalPublishRunnerResult(
        success: success,
        exitCode: exitCode,
        androidApkPaths: artifacts,
        windowsInstallDir: windowsInstallDir,
        windowsPackagePath: windowsPackagePath,
        windowsPackageSizeBytes: windowsPackageSizeBytes,
        pwaBuildSizeBytes: pwaBuildSizeBytes,
        output: stdoutBuffer.toString(),
        errorOutput: stderrBuffer.toString(),
        state: state,
      );
    } catch (e) {
      final message = 'Erro ao executar Central de Release Windows: $e';
      state = state.copyWith(running: false, errorMessage: message, finishedAt: DateTime.now());
      emit();
      log(message);
      return LocalPublishRunnerResult(
        success: false,
        exitCode: -1,
        androidApkPaths: artifacts,
        windowsInstallDir: windowsInstallDir,
        windowsPackagePath: windowsPackagePath,
        windowsPackageSizeBytes: windowsPackageSizeBytes,
        pwaBuildSizeBytes: pwaBuildSizeBytes,
        output: stdoutBuffer.toString(),
        errorOutput: message,
        state: state,
      );
    }
  }
}
