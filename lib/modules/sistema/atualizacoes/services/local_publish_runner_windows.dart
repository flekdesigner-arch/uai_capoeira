// lib/modules/sistema/atualizacoes/services/local_publish_runner_windows.dart
//
// =====================================================
// 🖥️ EXECUTOR WINDOWS DA AUTOMAÇÃO LOCAL - UAI
// =====================================================
//
// ATENÇÃO:
// Este arquivo usa dart:io.
// Ele NÃO pode ser importado diretamente em telas/serviços que compilam Web.
//
// O import seguro será feito depois por um arquivo factory com import condicional.
//
// Função:
// - executar PowerShell em modo automatico;
// - acompanhar stdout/stderr;
// - atualizar etapas da automação;
// - localizar APK final gerado.
// =====================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uai_capoeira/modules/sistema/atualizacoes/models/local_publish_automation_models.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/services/local_publish_platform_service.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/services/local_publish_runner_base.dart';

class LocalPublishRunnerWindows extends LocalPublishRunner {
  final LocalPublishPlatformInfo _platformInfo;

  LocalPublishRunnerWindows({
    LocalPublishPlatformInfo? platformInfo,
  }) : _platformInfo =
      platformInfo ?? const LocalPublishPlatformService().getInfo();

  @override
  LocalPublishPlatformInfo get platformInfo => _platformInfo;

  @override
  Future<LocalPublishRunnerResult> run({
    required LocalPublishRunnerConfig config,
    LocalPublishStateCallback? onState,
    LocalPublishLogCallback? onLog,
  }) async {
    var state = LocalPublishAutomationState.initial(
      available: platformInfo.canRunLocalAutomation,
      platformLabel: platformInfo.platformLabel,
    ).copyWith(
      running: true,
      startedAt: DateTime.now(),
      clearError: true,
      clearFinalApkPath: true,
    );

    void emit() => onState?.call(state);

    void log(String line) {
      if (line.trim().isEmpty) return;
      onLog?.call(line);
    }

    void setStep(
        String stepId,
        LocalPublishStepStatus status, {
          String? stepLog,
        }) {
      state = state.updateStep(
        stepId: stepId,
        status: status,
        log: stepLog,
      );
      emit();
    }

    emit();

    if (!platformInfo.canRunLocalAutomation) {
      final message = platformInfo.blockedReason;

      state = state.copyWith(
        running: false,
        errorMessage: message,
        finishedAt: DateTime.now(),
      );

      emit();
      log(message);

      return LocalPublishRunnerResult(
        success: false,
        exitCode: -1,
        finalApkPath: '',
        output: '',
        errorOutput: message,
        state: state,
      );
    }

    final scriptFile = File(config.scriptPath);
    final projectDir = Directory(config.projectDir);

    if (!projectDir.existsSync()) {
      final message = 'Pasta do projeto não encontrada: ${config.projectDir}';

      state = state.copyWith(
        running: false,
        errorMessage: message,
        finishedAt: DateTime.now(),
      );

      emit();
      log(message);

      return LocalPublishRunnerResult(
        success: false,
        exitCode: -1,
        finalApkPath: '',
        output: '',
        errorOutput: message,
        state: state,
      );
    }

    if (!scriptFile.existsSync()) {
      final message = 'Script não encontrado: ${config.scriptPath}';

      state = state.copyWith(
        running: false,
        errorMessage: message,
        finishedAt: DateTime.now(),
      );

      emit();
      log(message);

      return LocalPublishRunnerResult(
        success: false,
        exitCode: -1,
        finalApkPath: '',
        output: '',
        errorOutput: message,
        state: state,
      );
    }

    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();

    Process? process;

    try {
      log('Iniciando automação local no Windows...');
      log('Projeto: ${config.projectDir}');
      log('Script: ${config.scriptPath}');
      log('Versão: ${config.version}');

      process = await Process.start(
        'powershell.exe',
        [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          config.scriptPath,
          '-Auto',
        ],
        workingDirectory: config.projectDir,
        runInShell: false,
      );

      final stdoutDone = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        stdoutBuffer.writeln(line);
        log(line);
        _updateStateFromOutputLine(
          line: line,
          setStep: setStep,
        );
      }).asFuture<void>();

      final stderrDone = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        stderrBuffer.writeln(line);
        log(line);
      }).asFuture<void>();

      final exitCode = await process.exitCode;

      await Future.wait([
        stdoutDone,
        stderrDone,
      ]);

      final finalApkFile = File(config.expectedApkPath);
      final apkExists = finalApkFile.existsSync();

      if (exitCode == 0 && apkExists) {
        setStep(
          'locate_apk',
          LocalPublishStepStatus.success,
          stepLog: config.expectedApkPath,
        );

        state = state.copyWith(
          running: false,
          finalApkPath: config.expectedApkPath,
          finishedAt: DateTime.now(),
          clearError: true,
        );

        emit();

        return LocalPublishRunnerResult(
          success: true,
          exitCode: exitCode,
          finalApkPath: config.expectedApkPath,
          output: stdoutBuffer.toString(),
          errorOutput: stderrBuffer.toString(),
          state: state,
        );
      }

      final message = exitCode == 0
          ? 'Script finalizou, mas o APK final não foi encontrado em: ${config.expectedApkPath}'
          : 'Script finalizou com erro. Código de saída: $exitCode';

      if (!apkExists) {
        setStep(
          'locate_apk',
          LocalPublishStepStatus.error,
          stepLog: message,
        );
      }

      state = state.copyWith(
        running: false,
        errorMessage: message,
        finishedAt: DateTime.now(),
      );

      emit();

      return LocalPublishRunnerResult(
        success: false,
        exitCode: exitCode,
        finalApkPath: apkExists ? config.expectedApkPath : '',
        output: stdoutBuffer.toString(),
        errorOutput: stderrBuffer.toString().trim().isEmpty
            ? message
            : stderrBuffer.toString(),
        state: state,
      );
    } catch (e) {
      try {
        process?.kill();
      } catch (_) {}

      final message = 'Erro ao executar automação Windows: $e';

      state = state.copyWith(
        running: false,
        errorMessage: message,
        finishedAt: DateTime.now(),
      );

      emit();
      log(message);

      return LocalPublishRunnerResult(
        success: false,
        exitCode: -1,
        finalApkPath: '',
        output: stdoutBuffer.toString(),
        errorOutput: message,
        state: state,
      );
    }
  }

  void _updateStateFromOutputLine({
    required String line,
    required void Function(
        String stepId,
        LocalPublishStepStatus status, {
        String? stepLog,
        }) setStep,
  }) {
    final lower = line.toLowerCase();

    if (lower.contains('limpando build antigo')) {
      setStep('flutter_clean', LocalPublishStepStatus.running);
      return;
    }

    if (lower.contains('deleting build') ||
        lower.contains('deleting .dart_tool')) {
      return;
    }

    if (lower.contains('baixando dependencias')) {
      setStep('flutter_clean', LocalPublishStepStatus.success);
      setStep('flutter_pub_get', LocalPublishStepStatus.running);
      return;
    }

    if (lower.contains('got dependencies')) {
      setStep('flutter_pub_get', LocalPublishStepStatus.success);
      return;
    }

    if (lower.contains('gerando build web')) {
      setStep('build_web', LocalPublishStepStatus.running);
      return;
    }

    if (lower.contains('compiled') && lower.contains('web')) {
      setStep('build_web', LocalPublishStepStatus.success);
      return;
    }

    if (lower.contains('publicando pwa') ||
        lower.contains('firebase deploy --only hosting')) {
      setStep('build_web', LocalPublishStepStatus.success);
      setStep('deploy_hosting', LocalPublishStepStatus.running);
      return;
    }

    if (lower.contains('pwa publicado com sucesso') ||
        lower.contains('deploy complete') ||
        lower.contains('hosting url')) {
      setStep('deploy_hosting', LocalPublishStepStatus.success);
      return;
    }

    if (lower.contains('gerando apk release')) {
      setStep('deploy_hosting', LocalPublishStepStatus.success);
      setStep('build_apk', LocalPublishStepStatus.running);
      return;
    }

    if (lower.contains('built build\\app\\outputs\\flutter-apk\\app-release.apk') ||
        lower.contains('built build/app/outputs/flutter-apk/app-release.apk')) {
      setStep('build_apk', LocalPublishStepStatus.success);
      setStep('locate_apk', LocalPublishStepStatus.running);
      return;
    }

    if (lower.contains('apk menor gerado') ||
        lower.contains('apk pronto para subir')) {
      setStep('build_apk', LocalPublishStepStatus.success);
      setStep('locate_apk', LocalPublishStepStatus.success);
      return;
    }

    if (lower.contains('erro:') ||
        lower.contains('build failed') ||
        lower.contains('exception')) {
      setStep('build_apk', LocalPublishStepStatus.error, stepLog: line);
      return;
    }
  }
}
