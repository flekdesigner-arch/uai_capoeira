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

  LocalPublishRunnerWindows({LocalPublishPlatformInfo? platformInfo})
    : _platformInfo =
          platformInfo ?? const LocalPublishPlatformService().getInfo();

  @override
  LocalPublishPlatformInfo get platformInfo => _platformInfo;

  @override
  Future<LocalPublishRunnerResult> run({
    required LocalPublishRunnerConfig config,
    LocalPublishStateCallback? onState,
    LocalPublishLogCallback? onLog,
  }) async {
    var state =
        LocalPublishAutomationState.initial(
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
      state = state.updateStep(stepId: stepId, status: status, log: stepLog);
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

      final stdoutDone = _listenProcessOutput(
        stream: process.stdout,
        buffer: stdoutBuffer,
        onLine: (line) {
          log(line);
          _updateStateFromOutputLine(line: line, setStep: setStep);
        },
      );

      final stderrDone = _listenProcessOutput(
        stream: process.stderr,
        buffer: stderrBuffer,
        onLine: log,
      );

      final exitCode = await process.exitCode;

      await Future.wait([stdoutDone, stderrDone]);

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
        setStep('locate_apk', LocalPublishStepStatus.error, stepLog: message);
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

  Future<void> _listenProcessOutput({
    required Stream<List<int>> stream,
    required StringBuffer buffer,
    required void Function(String line) onLine,
  }) {
    final completer = Completer<void>();
    final pending = StringBuffer();

    late final StreamSubscription<List<int>> subscription;
    subscription = stream.listen(
      (bytes) {
        final text = _decodeProcessOutput(bytes);
        if (text.isEmpty) return;

        pending.write(text);
        final content = pending.toString();
        final lines = const LineSplitter().convert(content);

        pending.clear();

        final endsWithLineBreak =
            content.endsWith('\n') || content.endsWith('\r');
        final completedCount = endsWithLineBreak
            ? lines.length
            : lines.length - 1;

        for (var i = 0; i < completedCount; i++) {
          final line = lines[i];
          buffer.writeln(line);
          onLine(line);
        }

        if (!endsWithLineBreak && lines.isNotEmpty) {
          pending.write(lines.last);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        final line = 'Falha ao ler saída do processo: $error';
        buffer.writeln(line);
        onLine(line);
      },
      onDone: () {
        final rest = pending.toString();
        if (rest.trim().isNotEmpty) {
          buffer.writeln(rest);
          onLine(rest);
        }
        completer.complete();
      },
      cancelOnError: false,
    );

    return completer.future.whenComplete(subscription.cancel);
  }

  String _decodeProcessOutput(List<int> bytes) {
    if (bytes.isEmpty) return '';

    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      try {
        return latin1.decode(bytes, allowInvalid: true);
      } catch (_) {
        return String.fromCharCodes(bytes);
      }
    }
  }

  void _updateStateFromOutputLine({
    required String line,
    required void Function(
      String stepId,
      LocalPublishStepStatus status, {
      String? stepLog,
    })
    setStep,
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

    if (lower.contains(
          'built build\\app\\outputs\\flutter-apk\\app-release.apk',
        ) ||
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
