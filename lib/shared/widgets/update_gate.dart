// lib/shared/widgets/update_gate.dart
//
// =====================================================
// 🛡️ UPDATE GATE - BLOQUEIO DE VERSÃO OBRIGATÓRIA
// =====================================================
//
// Este widget verifica se a versão instalada do app pode continuar usando
// o sistema.
//
// Se a atualização for obrigatória e a versão local estiver abaixo da
// versão mínima, ele bloqueia o conteúdo e mostra uma tela educada para
// atualizar.
//
// Uso futuro no main.dart:
//
// home: kIsWeb
//     ? PwaEntradaInteligente()
//     : UpdateGate(child: SplashAuthScreen()),
//
// Mas no seu caso vamos encaixar com cuidado no próximo passo,
// para não quebrar o fluxo do PWA/Landing/AuthCheck.
//
// =====================================================

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/services/app_update_check_service.dart';
import 'package:uai_capoeira/core/services/atualizacao_direta_service.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

class UpdateGate extends StatefulWidget {
  final Widget child;

  /// Se true, ignora completamente o bloqueio no Web/PWA.
  ///
  /// Recomendo manter true porque atualização direta de APK só faz sentido
  /// no Android APK. O PWA atualiza por deploy/cache/service worker.
  final bool ignorarWeb;

  const UpdateGate({super.key, required this.child, this.ignorarWeb = true});

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  final AppUpdateCheckService _checkService = AppUpdateCheckService();
  final AtualizacaoDiretaService _atualizacaoService =
      AtualizacaoDiretaService();

  late Future<AppUpdateStatus> _statusFuture;

  bool _baixando = false;

  @override
  void initState() {
    super.initState();
    _statusFuture = _checkService.verificarStatus();
  }

  Future<void> _reverificar() async {
    setState(() {
      _statusFuture = _checkService.verificarStatus();
    });
  }

  Future<void> _atualizarAgora(AppUpdateStatus status) async {
    if (_baixando) return;

    setState(() => _baixando = true);

    try {
      await _atualizacaoService.baixarEInstalarComFeedback(
        context,
        status.versaoDestino,
      );
    } finally {
      if (mounted) {
        setState(() => _baixando = false);
      }
    }
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance())
        .abs();

    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  Color _softFill(Color color, Color base, [double opacity = 0.10]) {
    return Color.alphaBlend(color.withOpacity(opacity), base);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.ignorarWeb && kIsWeb) {
      return widget.child;
    }

    return FutureBuilder<AppUpdateStatus>(
      future: _statusFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return _buildLoading();
        }

        if (snapshot.hasError) {
          return widget.child;
        }

        final status = snapshot.data;

        if (status == null) {
          return widget.child;
        }

        if (!status.deveBloquear) {
          return widget.child;
        }

        return _buildBloqueio(status);
      },
    );
  }

  Widget _buildLoading() {
    final t = context.uai;

    return Scaffold(
      backgroundColor: t.background,
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(22),
          padding: const EdgeInsets.all(22),
          constraints: const BoxConstraints(maxWidth: 360),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(t.cardRadius + 4),
            border: Border.all(color: t.border),
            boxShadow: t.softShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: t.primary),
              const SizedBox(height: 14),
              Text(
                'Verificando versão do app...',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBloqueio(AppUpdateStatus status) {
    final t = context.uai;
    final danger = _ensureVisible(t.error, t.card);
    final onDanger = _readableOn(danger);

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: t.background,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Container(
                  decoration: BoxDecoration(
                    color: t.card,
                    borderRadius: BorderRadius.circular(t.cardRadius + 6),
                    border: Border.all(color: t.border),
                    boxShadow: t.cardShadow,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildHeaderBloqueio(danger: danger, onDanger: onDanger),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                        child: Column(
                          children: [
                            _buildVersoes(status),
                            const SizedBox(height: 14),
                            _buildMensagem(status),
                            const SizedBox(height: 14),
                            _buildChangelog(status),
                            const SizedBox(height: 14),
                            _buildAvisoSeguranca(),
                          ],
                        ),
                      ),
                      _buildRodape(status, danger, onDanger),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderBloqueio({
    required Color danger,
    required Color onDanger,
  }) {
    final t = context.uai;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            danger,
            Color.alphaBlend(Colors.black.withOpacity(0.14), danger),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(t.cardRadius + 6),
          topRight: Radius.circular(t.cardRadius + 6),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: onDanger.withOpacity(0.14),
              borderRadius: BorderRadius.circular(t.buttonRadius + 5),
              border: Border.all(color: onDanger.withOpacity(0.16)),
            ),
            child: Icon(Icons.lock_clock_rounded, color: onDanger, size: 34),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Atualização necessária',
                  style: TextStyle(
                    color: onDanger,
                    fontSize: 22,
                    height: 1.08,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Para continuar usando o UAI Capoeira com segurança, atualize o APK.',
                  style: TextStyle(
                    color: onDanger.withOpacity(0.84),
                    fontSize: 12.5,
                    height: 1.28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVersoes(AppUpdateStatus status) {
    final t = context.uai;
    final danger = _ensureVisible(t.error, t.card);

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          _versionPill(
            label: 'SUA VERSÃO',
            value: status.versaoLocal,
            color: t.textMuted,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Icon(Icons.arrow_forward_rounded, color: danger, size: 24),
          ),
          _versionPill(
            label: 'NECESSÁRIA',
            value: status.versaoDestino,
            color: danger,
          ),
        ],
      ),
    );
  }

  Widget _versionPill({
    required String label,
    required String value,
    required Color color,
  }) {
    final t = context.uai;
    final visible = _ensureVisible(color, t.card);
    final onColor = _readableOn(visible);

    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 5),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              color: visible,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: onColor,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMensagem(AppUpdateStatus status) {
    final t = context.uai;
    final danger = _ensureVisible(t.error, t.card);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _softFill(danger, t.card, 0.07),
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: danger.withOpacity(0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              status.mensagem.trim().isEmpty
                  ? 'Esta atualização corrige pontos importantes e evita falhas futuras no sistema.'
                  : status.mensagem,
              style: TextStyle(
                color: t.textPrimary,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChangelog(AppUpdateStatus status) {
    final sections = <Widget>[
      if (status.implementacoes.isNotEmpty)
        _changeSection(
          icon: Icons.add_circle_outline_rounded,
          title: 'Implementado',
          items: status.implementacoes,
        ),
      if (status.melhorias.isNotEmpty)
        _changeSection(
          icon: Icons.trending_up_rounded,
          title: 'Melhorias',
          items: status.melhorias,
        ),
      if (status.correcoes.isNotEmpty)
        _changeSection(
          icon: Icons.bug_report_rounded,
          title: 'Correções',
          items: status.correcoes,
        ),
      if (status.removidos.isNotEmpty)
        _changeSection(
          icon: Icons.remove_circle_outline_rounded,
          title: 'Removido',
          items: status.removidos,
        ),
    ];

    if (sections.isEmpty) {
      return _fallbackChangelog();
    }

    return Column(
      children: [
        for (final section in sections) ...[section, const SizedBox(height: 9)],
      ],
    );
  }

  Widget _fallbackChangelog() {
    return _changeSection(
      icon: Icons.fact_check_rounded,
      title: 'O que muda',
      items: const [
        'Melhorias de estabilidade',
        'Correções importantes',
        'Compatibilidade com a versão atual do sistema',
      ],
    );
  }

  Widget _changeSection({
    required IconData icon,
    required String title,
    required List<String> items,
  }) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.card);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: primary, size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final item in items.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '•',
                    style: TextStyle(
                      color: primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(
                        color: t.textSecondary,
                        height: 1.28,
                        fontSize: 12.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (items.length > 5)
            Text(
              '+ ${items.length - 5} item(ns) no histórico da versão',
              style: TextStyle(
                color: t.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAvisoSeguranca() {
    final t = context.uai;
    final warning = _ensureVisible(t.warning, t.card);

    return Text(
      'O uso do app ficará liberado novamente após instalar a versão necessária.',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: warning,
        height: 1.28,
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _buildRodape(AppUpdateStatus status, Color danger, Color onDanger) {
    final t = context.uai;

    return Container(
      padding: const EdgeInsets.fromLTRB(15, 12, 15, 15),
      decoration: BoxDecoration(
        color: t.card,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            onPressed: _baixando ? null : () => _atualizarAgora(status),
            icon: _baixando
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: onDanger,
                    ),
                  )
                : const Icon(Icons.download_rounded),
            label: Text(_baixando ? 'Preparando...' : 'ATUALIZAR AGORA'),
            style: ElevatedButton.styleFrom(
              backgroundColor: danger,
              foregroundColor: onDanger,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(t.buttonRadius),
              ),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _baixando ? null : _reverificar,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Já atualizei, verificar novamente'),
            style: TextButton.styleFrom(
              foregroundColor: t.textSecondary,
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
