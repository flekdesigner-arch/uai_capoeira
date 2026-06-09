// lib/core/services/atualizacao_dialog_service.dart
//
// =====================================================
// 🚀 SERVIÇO DE DIÁLOGO DE ATUALIZAÇÃO - UAI CAPOEIRA
// =====================================================
//
// Refatorado para o Laboratório de Atualizações.
//
// Agora ele lê:
// configuracoes/app
//   versao_atual
//   versao_minima_obrigatoria
//   atualizacao_obrigatoria
//   ultima_versao_id
//   titulo_atualizacao
//   mensagem_atualizacao
//
// E, quando existir, também lê:
// versoes_app/{ultima_versao_id}
//
// Para mostrar changelog real:
// - Melhorias
// - Correções
// - Implementações
// - Removidos
//
// Comportamento:
// - Atualização opcional: usuário pode tocar em "Agora não".
// - Atualização obrigatória: usuário não consegue fechar o diálogo pelo botão
//   "Agora não" nem clicando fora.
// - Visual acompanha o tema atual do app usando context.uai.
// =====================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/services/atualizacao_direta_service.dart';
import 'package:uai_capoeira/core/services/versao_service.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/models/app_version_model.dart';

class AtualizacaoDialogService {
  static final AtualizacaoDialogService _instance =
  AtualizacaoDialogService._internal();

  factory AtualizacaoDialogService() => _instance;

  AtualizacaoDialogService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final VersaoService _versaoService = VersaoService();
  final AtualizacaoDiretaService _atualizacaoService =
  AtualizacaoDiretaService();

  bool _dialogoJaMostrado = false;

  // =====================================================
  // 🔥 VERIFICAR E MOSTRAR DIÁLOGO
  // =====================================================
  Future<void> verificarEMostrarDialogo(BuildContext context) async {
    if (_dialogoJaMostrado) return;

    // =====================================================
    // 🌐 PWA / WEB
    // =====================================================
    // Atualização direta por APK só faz sentido no Android.
    // No PWA, a atualização acontece por deploy/cache/service worker.
    // Então não mostramos diálogo nem bloqueio de APK no navegador.
    // Isso evita erro: Unsupported operation: Platform._operatingSystem.
    // =====================================================
    if (kIsWeb) {
      debugPrint('🌐 Atualização APK ignorada no PWA/Web.');
      return;
    }

    try {
      final versaoLocal = await _versaoService.getVersaoLocal();

      final configDoc = await _firestore
          .collection('configuracoes')
          .doc('app')
          .get(const GetOptions(source: Source.server));

      final config = configDoc.data() ?? {};

      final versaoAtualServidor =
      (config['versao_atual'] ?? '1.0.0').toString().trim();

      if (versaoAtualServidor.isEmpty) return;

      final String ultimaVersaoId =
      (config['ultima_versao_id'] ?? '').toString().trim();

      final bool atualizacaoObrigatoria =
          config['atualizacao_obrigatoria'] == true;

      final String versaoMinimaObrigatoria =
      (config['versao_minima_obrigatoria'] ?? '').toString().trim();

      final bool existeVersaoNova = _compararVersoes(
        versaoLocal,
        versaoAtualServidor,
      );

      final bool estaAbaixoDaMinima = versaoMinimaObrigatoria.isNotEmpty
          ? _compararVersoes(versaoLocal, versaoMinimaObrigatoria)
          : false;

      final bool deveBloquear =
          atualizacaoObrigatoria == true && estaAbaixoDaMinima;

      if (!existeVersaoNova && !deveBloquear) {
        debugPrint(
          '✅ App atualizado. Local: $versaoLocal | Servidor: $versaoAtualServidor',
        );
        return;
      }

      final apkExiste = await _atualizacaoService.apkExiste(versaoAtualServidor);

      if (!apkExiste) {
        debugPrint(
          '⚠️ Existe versão nova ($versaoAtualServidor), '
              'mas o APK não foi encontrado no Storage.',
        );
        return;
      }

      AppVersionModel? versionModel;

      if (ultimaVersaoId.isNotEmpty) {
        versionModel = await _buscarVersaoPorId(ultimaVersaoId);
      }

      versionModel ??= await _buscarVersaoPorVersao(versaoAtualServidor);

      if (!context.mounted) return;

      _dialogoJaMostrado = true;

      await _mostrarDialogoAtualizacao(
        context: context,
        versaoAtual: versaoLocal,
        novaVersao: versaoAtualServidor,
        obrigatoria: deveBloquear,
        config: config,
        versionModel: versionModel,
      );
    } catch (e) {
      debugPrint('❌ Erro ao verificar atualização: $e');
    }
  }

  // =====================================================
  // 🔎 BUSCAR VERSÃO DO HISTÓRICO
  // =====================================================
  Future<AppVersionModel?> _buscarVersaoPorId(String versionId) async {
    try {
      final doc = await _firestore
          .collection('versoes_app')
          .doc(versionId)
          .get(const GetOptions(source: Source.server));

      if (!doc.exists) return null;

      return AppVersionModel.fromFirestore(doc);
    } catch (e) {
      debugPrint('⚠️ Não foi possível buscar versão por ID: $e');
      return null;
    }
  }

  Future<AppVersionModel?> _buscarVersaoPorVersao(String versao) async {
    try {
      final versionId = AppVersionModel.gerarVersionId(versao);
      if (versionId.isEmpty) return null;

      return _buscarVersaoPorId(versionId);
    } catch (e) {
      debugPrint('⚠️ Não foi possível buscar versão por número: $e');
      return null;
    }
  }

  // =====================================================
  // 🔍 COMPARAR VERSÕES
  // Retorna true se "servidor" for maior que "local".
  // =====================================================
  bool _compararVersoes(String local, String servidor) {
    try {
      final localParts = local.split('.').map(int.parse).toList();
      final servidorParts = servidor.split('.').map(int.parse).toList();

      final maxLength = localParts.length > servidorParts.length
          ? localParts.length
          : servidorParts.length;

      for (int i = 0; i < maxLength; i++) {
        final localValue = i < localParts.length ? localParts[i] : 0;
        final servidorValue = i < servidorParts.length ? servidorParts[i] : 0;

        if (servidorValue > localValue) return true;
        if (servidorValue < localValue) return false;
      }

      return false;
    } catch (e) {
      debugPrint('❌ Erro ao comparar versões: $e');
      return false;
    }
  }

  // =====================================================
  // 🎨 HELPERS DE TEMA
  // =====================================================
  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance()).abs();

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

  // =====================================================
  // 🎨 MOSTRAR DIÁLOGO DE ATUALIZAÇÃO
  // =====================================================
  Future<void> _mostrarDialogoAtualizacao({
    required BuildContext context,
    required String versaoAtual,
    required String novaVersao,
    required bool obrigatoria,
    required Map<String, dynamic> config,
    required AppVersionModel? versionModel,
  }) async {
    final t = context.uai;

    final String titulo = versionModel?.titulo.trim().isNotEmpty == true
        ? versionModel!.titulo
        : (config['titulo_atualizacao'] ?? 'Nova versão disponível')
        .toString();

    final String resumo = versionModel?.resumo.trim().isNotEmpty == true
        ? versionModel!.resumo
        : (config['mensagem_atualizacao'] ??
        'Atualize para receber melhorias e correções.')
        .toString();

    await showDialog<void>(
      context: context,
      barrierDismissible: !obrigatoria,
      builder: (dialogContext) {
        final dt = dialogContext.uai;
        final primary = _ensureVisible(dt.primary, dt.surface);
        final statusColor = obrigatoria
            ? _ensureVisible(dt.error, dt.surface)
            : _ensureVisible(dt.warning, dt.surface);

        return WillPopScope(
          onWillPop: () async => !obrigatoria,
          child: Dialog(
            insetPadding: const EdgeInsets.all(16),
            backgroundColor: Colors.transparent,
            elevation: 10,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Container(
                decoration: BoxDecoration(
                  color: dt.surface,
                  borderRadius: BorderRadius.circular(dt.cardRadius + 6),
                  border: Border.all(color: dt.border),
                  boxShadow: dt.cardShadow,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(dt.cardRadius + 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: obrigatoria
                                ? [
                              statusColor,
                              Color.alphaBlend(
                                Colors.black.withOpacity(0.16),
                                statusColor,
                              ),
                            ]
                                : [
                              primary,
                              Color.alphaBlend(
                                Colors.black.withOpacity(0.10),
                                primary,
                              ),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: _buildHeader(
                          tokensContext: dialogContext,
                          obrigatoria: obrigatoria,
                          titulo: titulo,
                        ),
                      ),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildVersaoBox(
                                context: dialogContext,
                                versaoAtual: versaoAtual,
                                novaVersao: novaVersao,
                                obrigatoria: obrigatoria,
                              ),
                              const SizedBox(height: 12),
                              _buildResumoBox(
                                context: dialogContext,
                                obrigatoria: obrigatoria,
                                resumo: resumo,
                              ),
                              const SizedBox(height: 12),
                              _buildChangelog(dialogContext, versionModel),
                              const SizedBox(height: 10),
                              _buildAvisoFinal(
                                context: dialogContext,
                                obrigatoria: obrigatoria,
                              ),
                            ],
                          ),
                        ),
                      ),
                      _buildBotoesRodape(
                        context: dialogContext,
                        novaVersao: novaVersao,
                        obrigatoria: obrigatoria,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    // Mantém compatibilidade com variável já carregada.
    // ignore: unnecessary_statements
    t;
  }

  Widget _buildHeader({
    required BuildContext tokensContext,
    required bool obrigatoria,
    required String titulo,
  }) {
    final t = tokensContext.uai;
    final primary = _ensureVisible(t.primary, t.surface);
    final statusColor = obrigatoria
        ? _ensureVisible(t.error, t.surface)
        : _ensureVisible(t.warning, t.surface);

    final headerColor = obrigatoria ? statusColor : primary;
    final onHeader = _readableOn(headerColor);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: onHeader.withOpacity(0.14),
              borderRadius: BorderRadius.circular(t.buttonRadius + 4),
              border: Border.all(color: onHeader.withOpacity(0.18)),
            ),
            child: Icon(
              obrigatoria
                  ? Icons.lock_clock_rounded
                  : Icons.system_update_alt_rounded,
              size: 31,
              color: onHeader,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  obrigatoria
                      ? 'Atualização necessária'
                      : 'Nova versão disponível',
                  style: TextStyle(
                    color: onHeader,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    height: 1.08,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  titulo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onHeader.withOpacity(0.84),
                    fontSize: 12.5,
                    height: 1.25,
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

  Widget _buildVersaoBox({
    required BuildContext context,
    required String versaoAtual,
    required String novaVersao,
    required bool obrigatoria,
  }) {
    final t = context.uai;
    final statusColor = obrigatoria
        ? _ensureVisible(t.error, t.card)
        : _ensureVisible(t.warning, t.card);

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildVersaoChip(
            context: context,
            label: 'ATUAL',
            value: versaoAtual,
            color: t.textMuted,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Icon(
              Icons.arrow_forward_rounded,
              color: statusColor,
              size: 24,
            ),
          ),
          _buildVersaoChip(
            context: context,
            label: obrigatoria ? 'OBRIGATÓRIA' : 'NOVA',
            value: novaVersao,
            color: statusColor,
          ),
        ],
      ),
    );
  }

  Widget _buildVersaoChip({
    required BuildContext context,
    required String label,
    required String value,
    required Color color,
  }) {
    final t = context.uai;
    final visibleColor = _ensureVisible(color, t.card);
    final onColor = _readableOn(visibleColor);

    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: t.textSecondary,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 5),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: visibleColor,
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

  Widget _buildResumoBox({
    required BuildContext context,
    required bool obrigatoria,
    required String resumo,
  }) {
    final t = context.uai;
    final color = obrigatoria ? t.error : t.info;
    final accent = _ensureVisible(color, t.card);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _softFill(accent, t.card, 0.07),
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: accent.withOpacity(0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            obrigatoria ? Icons.warning_amber_rounded : Icons.info_outline,
            color: accent,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              resumo.trim().isEmpty
                  ? 'Atualização com melhorias e correções importantes.'
                  : resumo,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChangelog(BuildContext context, AppVersionModel? version) {
    if (version == null) {
      return _buildFallbackBeneficios(context);
    }

    final sections = <Widget>[
      if (version.implementacoes.isNotEmpty)
        _buildChangelogSection(
          context: context,
          icon: Icons.add_circle_outline_rounded,
          title: 'Implementado',
          items: version.implementacoes,
        ),
      if (version.melhorias.isNotEmpty)
        _buildChangelogSection(
          context: context,
          icon: Icons.trending_up_rounded,
          title: 'Melhorias',
          items: version.melhorias,
        ),
      if (version.correcoes.isNotEmpty)
        _buildChangelogSection(
          context: context,
          icon: Icons.bug_report_rounded,
          title: 'Correções',
          items: version.correcoes,
        ),
      if (version.removidos.isNotEmpty)
        _buildChangelogSection(
          context: context,
          icon: Icons.remove_circle_outline_rounded,
          title: 'Removido',
          items: version.removidos,
        ),
    ];

    if (sections.isEmpty) {
      return _buildFallbackBeneficios(context);
    }

    return Column(
      children: [
        for (final section in sections) ...[
          section,
          const SizedBox(height: 9),
        ],
      ],
    );
  }

  Widget _buildFallbackBeneficios(BuildContext context) {
    final t = context.uai;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
      ),
      child: Column(
        children: [
          _buildLinhaBeneficio(
            context: context,
            icon: Icons.speed_rounded,
            texto: 'Desempenho otimizado',
          ),
          const SizedBox(height: 8),
          _buildLinhaBeneficio(
            context: context,
            icon: Icons.bug_report_rounded,
            texto: 'Correções e melhorias',
          ),
          const SizedBox(height: 8),
          _buildLinhaBeneficio(
            context: context,
            icon: Icons.security_rounded,
            texto: 'Compatibilidade atualizada',
          ),
        ],
      ),
    );
  }

  Widget _buildChangelogSection({
    required BuildContext context,
    required IconData icon,
    required String title,
    required List<String> items,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(t.primary, t.card);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLinhaBeneficio(
            context: context,
            icon: icon,
            texto: title,
            strong: true,
          ),
          const SizedBox(height: 7),
          for (final item in items.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '•',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 12.2,
                        height: 1.25,
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

  Widget _buildLinhaBeneficio({
    required BuildContext context,
    required IconData icon,
    required String texto,
    bool strong = false,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(t.primary, t.card);

    return Row(
      children: [
        Icon(
          icon,
          size: strong ? 19 : 18,
          color: accent,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            texto,
            style: TextStyle(
              fontSize: strong ? 13 : 12.5,
              color: strong ? t.textPrimary : t.textSecondary,
              fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAvisoFinal({
    required BuildContext context,
    required bool obrigatoria,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(obrigatoria ? t.error : t.warning, t.card);

    return Text(
      obrigatoria
          ? 'Esta atualização é necessária para evitar erros e garantir compatibilidade com o sistema.'
          : 'Você pode atualizar agora ou continuar usando e atualizar depois.',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: accent,
        fontSize: 11,
        height: 1.25,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildBotoesRodape({
    required BuildContext context,
    required String novaVersao,
    required bool obrigatoria,
  }) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.card);
    final danger = _ensureVisible(t.error, t.card);
    final actionColor = obrigatoria ? danger : primary;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: t.card,
        border: Border(
          top: BorderSide(color: t.border),
        ),
      ),
      child: Row(
        children: [
          if (!obrigatoria) ...[
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _dialogoJaMostrado = false;
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  side: BorderSide(color: t.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(t.buttonRadius),
                  ),
                ),
                child: Text(
                  'AGORA NÃO',
                  style: TextStyle(
                    color: t.textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                if (!obrigatoria) {
                  Navigator.pop(context);
                }

                _iniciarAtualizacao(context, novaVersao);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: actionColor,
                foregroundColor: _readableOn(actionColor),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                ),
                elevation: 3,
              ),
              icon: const Icon(Icons.download_rounded, size: 20),
              label: Text(
                obrigatoria ? 'ATUALIZAR AGORA' : 'ATUALIZAR',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // 📥 INICIAR ATUALIZAÇÃO
  // =====================================================
  void _iniciarAtualizacao(BuildContext context, String versao) {
    _atualizacaoService.baixarEInstalarComFeedback(context, versao);
  }

  // =====================================================
  // 🔄 RESETAR FLAG
  // =====================================================
  void resetarDialogoJaMostrado() {
    _dialogoJaMostrado = false;
  }
}
