// lib/modules/sistema/atualizacoes/widgets/local_publish_automation_panel.dart
//
// =====================================================
// 🚀 PAINEL VISUAL DA AUTOMAÇÃO WINDOWS - UAI
// =====================================================
//
// Este widget é seguro para APK, PWA e Windows.
// Não usa dart:io.
// Não executa comandos diretamente.
//
// Ele só mostra:
// - plataforma detectada;
// - botão "Publicar sem notificar";
// - progresso das etapas;
// - caminho do APK final;
// - logs do processo.
//
// A tela ControleAtualizacoesScreen será responsável por chamar o runner.
// =====================================================

import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/models/local_publish_automation_models.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/services/local_publish_platform_service.dart';

class LocalPublishAutomationPanel extends StatelessWidget {
  final LocalPublishPlatformInfo platformInfo;
  final LocalPublishAutomationState state;
  final String logText;
  final bool canStart;
  final VoidCallback? onRunFullAutomation;
  final VoidCallback? onRunBetaAutomation;
  final VoidCallback? onClearLog;

  const LocalPublishAutomationPanel({
    super.key,
    required this.platformInfo,
    required this.state,
    required this.logText,
    required this.canStart,
    required this.onRunFullAutomation,
    this.onRunBetaAutomation,
    required this.onClearLog,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final available = platformInfo.canRunLocalAutomation;
    final accent = available ? t.success : t.warning;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: accent.withAlpha(46)),
        boxShadow: t.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(platformInfo: platformInfo, state: state),
          const SizedBox(height: 13),
          if (!available) ...[
            _BlockedInfo(platformInfo: platformInfo),
          ] else ...[
            _ActionBox(
              state: state,
              canStart: canStart,
              onRunFullAutomation: onRunFullAutomation,
              onRunBetaAutomation: onRunBetaAutomation,
            ),
            const SizedBox(height: 13),
            _ProgressBox(state: state),
            const SizedBox(height: 13),
            _StepsList(state: state),
            if (state.finalApkPath != null &&
                state.finalApkPath!.trim().isNotEmpty) ...[
              const SizedBox(height: 13),
              _FinalApkBox(path: state.finalApkPath!),
            ],
            if (state.errorMessage != null &&
                state.errorMessage!.trim().isNotEmpty) ...[
              const SizedBox(height: 13),
              _ErrorBox(message: state.errorMessage!),
            ],
            const SizedBox(height: 13),
            _LogBox(logText: logText, onClearLog: onClearLog),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final LocalPublishPlatformInfo platformInfo;
  final LocalPublishAutomationState state;

  const _Header({required this.platformInfo, required this.state});

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final available = platformInfo.canRunLocalAutomation;
    final color = available ? t.success : t.warning;

    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Color.alphaBlend(color.withAlpha(31), t.cardAlt),
            borderRadius: BorderRadius.circular(t.buttonRadius),
            border: Border.all(color: color.withAlpha(41)),
          ),
          child: Icon(platformInfo.icon, color: color, size: 29),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'UAI Release Center',
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                available
                    ? 'Plataforma: ${platformInfo.platformLabel} • pronta para executar a esteira completa.'
                    : 'Plataforma: ${platformInfo.platformLabel} • automação local bloqueada.',
                style: TextStyle(
                  color: t.textSecondary,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _StatusChip(
          label: state.running
              ? 'Rodando'
              : available
              ? 'Liberado'
              : 'Bloqueado',
          color: state.running
              ? t.info
              : available
              ? t.success
              : t.warning,
        ),
      ],
    );
  }
}

class _ActionBox extends StatelessWidget {
  final LocalPublishAutomationState state;
  final bool canStart;
  final VoidCallback? onRunFullAutomation;
  final VoidCallback? onRunBetaAutomation;

  const _ActionBox({
    required this.state,
    required this.canStart,
    required this.onRunFullAutomation,
    required this.onRunBetaAutomation,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final disabled = state.running || !canStart;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Color.alphaBlend(t.primary.withAlpha(18), t.card),
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.primary.withAlpha(33)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 650;

          final info = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.auto_awesome_rounded, color: t.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Uma esteira completa: sincroniza versão/build, publica PWA, gera Android por arquitetura, instala a release Windows e publica o manifesto. A notificação continua manual para você testar primeiro.',
                  style: TextStyle(
                    color: t.textSecondary,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          );

          final productionButton = ElevatedButton.icon(
            onPressed: disabled ? null : onRunFullAutomation,
            icon: state.running
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.rocket_launch_rounded),
            label: const Text('Lançar produção'),
          );
          final betaButton = OutlinedButton.icon(
            onPressed: disabled ? null : onRunBetaAutomation,
            icon: const Icon(Icons.science_rounded),
            label: const Text('Gerar BETA'),
          );

          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [info, const SizedBox(height: 12), productionButton, const SizedBox(height: 8), betaButton],
            );
          }

          return Row(
            children: [
              Expanded(child: info),
              const SizedBox(width: 12),
              productionButton,
              const SizedBox(height: 8),
              betaButton,
            ],
          );
        },
      ),
    );
  }
}

class _ProgressBox extends StatelessWidget {
  final LocalPublishAutomationState state;

  const _ProgressBox({required this.state});

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final progress = state.progress.clamp(0.0, 1.0);
    final percent = (progress * 100).toStringAsFixed(0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                state.completed
                    ? 'Automação concluída'
                    : state.running
                    ? 'Executando processo'
                    : 'Progresso da automação',
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Text(
              '$percent%',
              style: TextStyle(
                color: t.textSecondary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: progress,
          minHeight: 9,
          borderRadius: BorderRadius.circular(999),
          backgroundColor: t.border.withAlpha(89),
        ),
      ],
    );
  }
}

class _StepsList extends StatelessWidget {
  final LocalPublishAutomationState state;

  const _StepsList({required this.state});

  static const _groups = <_ReleaseStepGroup>[
    _ReleaseStepGroup(
      title: 'Preparação',
      icon: Icons.tune_rounded,
      ids: {'save_draft', 'preflight', 'sync_version', 'flutter_clean', 'flutter_pub_get'},
    ),
    _ReleaseStepGroup(
      title: 'PWA',
      icon: Icons.language_rounded,
      ids: {'build_web', 'deploy_hosting'},
    ),
    _ReleaseStepGroup(
      title: 'Android',
      icon: Icons.android_rounded,
      ids: {'deploy_storage_rules', 'build_android', 'locate_apk', 'upload_apk'},
    ),
    _ReleaseStepGroup(
      title: 'Windows',
      icon: Icons.desktop_windows_rounded,
      ids: {'build_windows', 'install_windows'},
    ),
    _ReleaseStepGroup(
      title: 'Publicação',
      icon: Icons.cloud_done_rounded,
      ids: {'publish_version', 'notify_users'},
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final group in _groups) ...[
          _StepGroupCard(
            group: group,
            steps: state.steps.where((step) => group.ids.contains(step.id)).toList(),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ReleaseStepGroup {
  final String title;
  final IconData icon;
  final Set<String> ids;

  const _ReleaseStepGroup({
    required this.title,
    required this.icon,
    required this.ids,
  });
}

class _StepGroupCard extends StatelessWidget {
  final _ReleaseStepGroup group;
  final List<LocalPublishStep> steps;

  const _StepGroupCard({required this.group, required this.steps});

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final finished = steps.where((step) => step.status.isFinished).length;
    final running = steps.any((step) => step.status.isRunning);
    final hasError = steps.any((step) => step.status.isError);
    final color = hasError
        ? t.error
        : running
            ? t.info
            : (steps.isNotEmpty && finished == steps.length)
                ? t.success
                : t.primary;
    final progress = steps.isEmpty ? 0.0 : finished / steps.length;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withAlpha(9), t.cardAlt),
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: color.withAlpha(36)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(group.icon, color: color, size: 21),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  group.title,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                '$finished/${steps.length}',
                style: TextStyle(
                  color: t.textSecondary,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 5,
            borderRadius: BorderRadius.circular(999),
            backgroundColor: t.border.withAlpha(77),
            color: color,
          ),
          const SizedBox(height: 10),
          for (final step in steps) ...[
            _StepTile(step: step),
            if (step != steps.last) const SizedBox(height: 7),
          ],
        ],
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  final LocalPublishStep step;

  const _StepTile({required this.step});

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final color = _colorForStatus(context, step.status);

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withAlpha(15), t.cardAlt),
        borderRadius: BorderRadius.circular(t.buttonRadius),
        border: Border.all(color: color.withAlpha(28)),
      ),
      child: Row(
        children: [
          _StepIcon(status: step.status, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  step.description,
                  style: TextStyle(
                    color: t.textSecondary,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                if (step.log != null && step.log!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    step.log!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _StatusChip(label: step.status.label, color: color),
        ],
      ),
    );
  }

  Color _colorForStatus(BuildContext context, LocalPublishStepStatus status) {
    final t = context.uai;

    switch (status) {
      case LocalPublishStepStatus.pending:
        return t.textMuted;
      case LocalPublishStepStatus.running:
        return t.info;
      case LocalPublishStepStatus.success:
        return t.success;
      case LocalPublishStepStatus.error:
        return t.error;
      case LocalPublishStepStatus.skipped:
        return t.warning;
    }
  }
}

class _StepIcon extends StatelessWidget {
  final LocalPublishStepStatus status;
  final Color color;

  const _StepIcon({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withAlpha(36), t.card),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: status == LocalPublishStepStatus.running
            ? SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            : Icon(_iconForStatus(status), color: color, size: 20),
      ),
    );
  }

  IconData _iconForStatus(LocalPublishStepStatus status) {
    switch (status) {
      case LocalPublishStepStatus.pending:
        return Icons.radio_button_unchecked_rounded;
      case LocalPublishStepStatus.running:
        return Icons.sync_rounded;
      case LocalPublishStepStatus.success:
        return Icons.check_circle_rounded;
      case LocalPublishStepStatus.error:
        return Icons.error_rounded;
      case LocalPublishStepStatus.skipped:
        return Icons.skip_next_rounded;
    }
  }
}

class _BlockedInfo extends StatelessWidget {
  final LocalPublishPlatformInfo platformInfo;

  const _BlockedInfo({required this.platformInfo});

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Color.alphaBlend(t.warning.withAlpha(20), t.card),
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.warning.withAlpha(41)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_rounded, color: t.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              platformInfo.blockedReason,
              style: TextStyle(
                color: t.textSecondary,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FinalApkBox extends StatelessWidget {
  final String path;

  const _FinalApkBox({required this.path});

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Color.alphaBlend(t.success.withAlpha(20), t.card),
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.success.withAlpha(41)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.folder_zip_rounded, color: t.success),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'APK final localizado:\n$path',
              style: TextStyle(
                color: t.textSecondary,
                height: 1.35,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;

  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Color.alphaBlend(t.error.withAlpha(20), t.card),
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.error.withAlpha(41)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: t.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: t.textSecondary,
                height: 1.35,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogBox extends StatelessWidget {
  final String logText;
  final VoidCallback? onClearLog;

  const _LogBox({required this.logText, required this.onClearLog});

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final hasLog = logText.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 11, 8, 8),
            child: Row(
              children: [
                Icon(Icons.terminal_rounded, color: t.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Log da automação',
                    style: TextStyle(
                      color: t.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: hasLog ? onClearLog : null,
                  icon: const Icon(Icons.cleaning_services_rounded, size: 18),
                  label: const Text('Limpar'),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 90, maxHeight: 220),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(222),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(t.cardRadius),
                bottomRight: Radius.circular(t.cardRadius),
              ),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                hasLog ? logText.trim() : 'Nenhum log ainda.',
                style: TextStyle(
                  color: hasLog ? Colors.white : Colors.white.withAlpha(140),
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withAlpha(31), t.card),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(41)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
      ),
    );
  }
}
