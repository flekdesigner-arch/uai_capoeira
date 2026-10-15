// lib/modules/sistema/atualizacoes/models/local_publish_automation_models.dart
//
// =====================================================
// 🚀 MODELOS DA AUTOMAÇÃO LOCAL DE PUBLICAÇÃO - UAI
// =====================================================
//
// Este arquivo é seguro para APK, PWA e Windows.
// Não usa dart:io.
// Não executa script.
// Apenas organiza os status/etapas/resultados da automação.
//
// Ele será usado na versão 64 para mostrar no Laboratório:
// - progresso do deploy PWA;
// - progresso da geração do APK;
// - caminho do APK final;
// - sucesso/erro de cada etapa.
// =====================================================

import 'package:flutter/foundation.dart';

enum LocalPublishStepStatus { pending, running, success, error, skipped }

extension LocalPublishStepStatusX on LocalPublishStepStatus {
  String get label {
    switch (this) {
      case LocalPublishStepStatus.pending:
        return 'Pendente';
      case LocalPublishStepStatus.running:
        return 'Executando';
      case LocalPublishStepStatus.success:
        return 'Concluído';
      case LocalPublishStepStatus.error:
        return 'Erro';
      case LocalPublishStepStatus.skipped:
        return 'Ignorado';
    }
  }

  bool get isFinished {
    return this == LocalPublishStepStatus.success ||
        this == LocalPublishStepStatus.error ||
        this == LocalPublishStepStatus.skipped;
  }

  bool get isSuccess => this == LocalPublishStepStatus.success;
  bool get isRunning => this == LocalPublishStepStatus.running;
  bool get isError => this == LocalPublishStepStatus.error;
}

@immutable
class LocalPublishStep {
  final String id;
  final String title;
  final String description;
  final LocalPublishStepStatus status;
  final String? log;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  const LocalPublishStep({
    required this.id,
    required this.title,
    required this.description,
    this.status = LocalPublishStepStatus.pending,
    this.log,
    this.startedAt,
    this.finishedAt,
  });

  LocalPublishStep copyWith({
    String? id,
    String? title,
    String? description,
    LocalPublishStepStatus? status,
    String? log,
    DateTime? startedAt,
    DateTime? finishedAt,
    bool clearLog = false,
  }) {
    return LocalPublishStep(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      log: clearLog ? null : log ?? this.log,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'status': status.name,
      'log': log,
      'startedAt': startedAt?.toIso8601String(),
      'finishedAt': finishedAt?.toIso8601String(),
    };
  }

  static List<LocalPublishStep> defaultSteps() {
    return const [
      LocalPublishStep(id: 'save_draft', title: 'Preparar release', description: 'Salva changelog e sincroniza versão/build.'),
      LocalPublishStep(id: 'preflight', title: 'Verificar ambiente', description: 'Valida Flutter, Firebase, projeto e arquivos essenciais.'),
      LocalPublishStep(id: 'sync_version', title: 'Sincronizar versão', description: 'Atualiza pubspec.yaml com a versão e build da Central.'),
      LocalPublishStep(id: 'flutter_clean', title: 'Limpar projeto', description: 'Remove builds antigos.'),
      LocalPublishStep(id: 'flutter_pub_get', title: 'Dependências', description: 'Atualiza as dependências Flutter.'),
      LocalPublishStep(id: 'build_web', title: 'Gerar PWA', description: 'Gera o PWA release.'),
      LocalPublishStep(id: 'deploy_hosting', title: 'Publicar PWA', description: 'Publica no Firebase Hosting.'),
      LocalPublishStep(id: 'deploy_storage_rules', title: 'Sincronizar Storage', description: 'Publica as regras necessárias para a árvore releases/.'),
      LocalPublishStep(id: 'build_android', title: 'Android multi-ABI', description: 'Gera ARM32, ARM64 e x86_64 separados.'),
      LocalPublishStep(id: 'locate_apk', title: 'Validar APKs', description: 'Confere os três APKs e seus tamanhos.'),
      LocalPublishStep(id: 'build_windows', title: 'Gerar Windows', description: 'Gera o build Windows release.'),
      LocalPublishStep(id: 'install_windows', title: 'Instalar Windows', description: 'Atualiza C:\\UAI Capoeira e o atalho da Área de Trabalho.'),
      LocalPublishStep(id: 'upload_apk', title: 'Enviar Android', description: 'Envia cada ABI para a árvore releases/ no Storage.'),
      LocalPublishStep(id: 'publish_version', title: 'Publicar manifesto', description: 'Publica a release e os artefatos no Firestore.'),
      LocalPublishStep(id: 'notify_users', title: 'Notificar usuários', description: 'Fica manual para você testar antes de avisar.'),
    ];
  }
}

@immutable
class LocalPublishAutomationState {
  final bool available;
  final bool running;
  final String platformLabel;
  final String? currentStepId;
  final String? finalApkPath;
  final String? errorMessage;
  final List<LocalPublishStep> steps;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  const LocalPublishAutomationState({
    required this.available,
    required this.running,
    required this.platformLabel,
    required this.steps,
    this.currentStepId,
    this.finalApkPath,
    this.errorMessage,
    this.startedAt,
    this.finishedAt,
  });

  factory LocalPublishAutomationState.initial({
    required bool available,
    required String platformLabel,
  }) {
    return LocalPublishAutomationState(
      available: available,
      running: false,
      platformLabel: platformLabel,
      steps: LocalPublishStep.defaultSteps(),
    );
  }

  LocalPublishAutomationState copyWith({
    bool? available,
    bool? running,
    String? platformLabel,
    String? currentStepId,
    String? finalApkPath,
    String? errorMessage,
    List<LocalPublishStep>? steps,
    DateTime? startedAt,
    DateTime? finishedAt,
    bool clearCurrentStep = false,
    bool clearFinalApkPath = false,
    bool clearError = false,
  }) {
    return LocalPublishAutomationState(
      available: available ?? this.available,
      running: running ?? this.running,
      platformLabel: platformLabel ?? this.platformLabel,
      currentStepId: clearCurrentStep
          ? null
          : currentStepId ?? this.currentStepId,
      finalApkPath: clearFinalApkPath
          ? null
          : finalApkPath ?? this.finalApkPath,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      steps: steps ?? this.steps,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
    );
  }

  LocalPublishAutomationState updateStep({
    required String stepId,
    required LocalPublishStepStatus status,
    String? log,
  }) {
    final now = DateTime.now();

    final updatedSteps = steps.map((step) {
      if (step.id != stepId) return step;

      return step.copyWith(
        status: status,
        log: log,
        startedAt: status == LocalPublishStepStatus.running
            ? step.startedAt ?? now
            : step.startedAt,
        finishedAt: status.isFinished ? now : step.finishedAt,
      );
    }).toList();

    return copyWith(
      steps: updatedSteps,
      currentStepId: status.isFinished ? currentStepId : stepId,
    );
  }

  double get progress {
    if (steps.isEmpty) return 0;

    final finished = steps.where((step) => step.status.isFinished).length;
    return finished / steps.length;
  }

  bool get hasError {
    return errorMessage != null ||
        steps.any((step) => step.status == LocalPublishStepStatus.error);
  }

  bool get completed {
    return steps.isNotEmpty &&
        steps.every((step) =>
            step.status == LocalPublishStepStatus.success ||
            step.status == LocalPublishStepStatus.skipped);
  }
}

@immutable
class LocalCommandResult {
  final bool success;
  final int exitCode;
  final String stdout;
  final String stderr;
  final String commandLabel;

  const LocalCommandResult({
    required this.success,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.commandLabel,
  });

  String get fullLog {
    final buffer = StringBuffer();

    if (stdout.trim().isNotEmpty) {
      buffer.writeln(stdout.trim());
    }

    if (stderr.trim().isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.writeln(stderr.trim());
    }

    return buffer.toString().trim();
  }
}
