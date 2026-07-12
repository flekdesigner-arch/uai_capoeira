import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudo_ciclo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudo_model.dart';

class EstudoArtigoRenderer extends StatelessWidget {
  final EstudoModel estudo;
  final bool mostrarMetadados;

  const EstudoArtigoRenderer({
    super.key,
    required this.estudo,
    this.mostrarMetadados = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (estudo.capaUrl.isNotEmpty) _buildCapa(context),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(t.cardRadius + 2),
            border: Border.all(color: t.border),
            boxShadow: t.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip(
                    context,
                    Icons.article_rounded,
                    'Estudo ${estudo.numero.toString().padLeft(3, '0')}',
                  ),
                  if (estudo.cicloTituloSnapshot.isNotEmpty)
                    _chip(
                      context,
                      Icons.timeline_rounded,
                      estudo.cicloTituloSnapshot,
                    ),
                  if (estudo.duracaoEstimadaMin > 0)
                    _chip(
                      context,
                      Icons.schedule_rounded,
                      '${estudo.duracaoEstimadaMin} min',
                    ),
                  if (mostrarMetadados) _statusChip(context),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                estudo.titulo.isEmpty ? 'Estudo sem título' : estudo.titulo,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 28,
                  height: 1.08,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (estudo.subtitulo.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  estudo.subtitulo,
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 17,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (estudo.perguntaPrincipal.isNotEmpty) ...[
                const SizedBox(height: 16),
                _callout(
                  context,
                  Icons.help_outline_rounded,
                  'Pergunta principal',
                  estudo.perguntaPrincipal,
                ),
              ],
              if (estudo.resumo.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  estudo.resumo,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 16,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (estudo.textoAprofundado.isNotEmpty)
          _section(
            context,
            'Texto aprofundado',
            estudo.textoAprofundado,
            Icons.menu_book_rounded,
          ),
        if (estudo.imagensUrls.isNotEmpty) _imagensSection(context),
        if (estudo.mitoOuFato.isNotEmpty)
          _section(
            context,
            'Mito ou fato',
            estudo.mitoOuFato,
            Icons.fact_check_rounded,
          ),
        if (estudo.voceSabia.isNotEmpty)
          _section(
            context,
            'Você sabia?',
            estudo.voceSabia,
            Icons.lightbulb_outline_rounded,
          ),
        if (estudo.palavrasImportantesLista.isNotEmpty)
          _listSection(
            context,
            'Palavras importantes',
            estudo.palavrasImportantesLista,
            Icons.sell_rounded,
          ),
        if (estudo.reflexaoFinal.isNotEmpty)
          _section(
            context,
            'Reflexão final',
            estudo.reflexaoFinal,
            Icons.psychology_rounded,
          ),
        if (estudo.videoYoutubeUrl.isNotEmpty || estudo.linkExterno.isNotEmpty)
          _linksSection(context),
        if (estudo.fontesLista.isNotEmpty)
          _listSection(
            context,
            'Fontes e referências',
            estudo.fontesLista,
            Icons.source_rounded,
          ),
        if (mostrarMetadados) _visibilitySection(context),
      ],
    );
  }

  Widget _buildCapa(BuildContext context) {
    final t = context.uai;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        border: Border.all(color: t.border),
        color: t.cardAlt,
      ),
      child: AspectRatio(
        aspectRatio: 16 / 7,
        child: Image.network(
          estudo.capaUrl,
          fit: BoxFit.cover,
          alignment: Alignment(
            (estudo.capaFocoX * 2) - 1,
            (estudo.capaFocoY * 2) - 1,
          ),
          errorBuilder: (context, error, stackTrace) => Center(
            child: Icon(
              Icons.broken_image_rounded,
              color: t.textMuted,
              size: 42,
            ),
          ),
        ),
      ),
    );
  }

  Widget _imagensSection(BuildContext context) {
    final t = context.uai;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.photo_library_rounded, color: t.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Imagens do estudo',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...estudo.imagensUrls.map(
            (url) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: t.cardAlt,
                borderRadius: BorderRadius.circular(t.cardRadius),
                border: Border.all(color: t.border),
              ),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        color: t.primary,
                        strokeWidth: 2,
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => Center(
                    child: Text(
                      'Imagem não carregada',
                      style: TextStyle(
                        color: t.textMuted,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(
    BuildContext context,
    String title,
    String text,
    IconData icon,
  ) {
    final t = context.uai;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: t.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            text,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 15,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _listSection(
    BuildContext context,
    String title,
    List<String> items,
    IconData icon,
  ) {
    final t = context.uai;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: t.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items.map((item) => _textPill(context, item)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _linksSection(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (estudo.videoYoutubeUrl.isNotEmpty)
            _linkCard(
              context,
              Icons.smart_display_rounded,
              'Vídeo do YouTube',
              estudo.videoYoutubeUrl,
            ),
          if (estudo.linkExterno.isNotEmpty) ...[
            if (estudo.videoYoutubeUrl.isNotEmpty) const SizedBox(height: 8),
            _linkCard(
              context,
              Icons.open_in_new_rounded,
              'Link externo',
              estudo.linkExterno,
            ),
          ],
        ],
      ),
    );
  }

  Widget _linkCard(
    BuildContext context,
    IconData icon,
    String title,
    String url,
  ) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Row(
        children: [
          Icon(icon, color: t.primary, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  url,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _visibilitySection(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _chip(
            context,
            estudo.mostrarNaLinhaDoTempo
                ? Icons.visibility_rounded
                : Icons.visibility_off_rounded,
            estudo.mostrarNaLinhaDoTempo
                ? 'Aparece na linha do tempo'
                : 'Fora da linha do tempo',
          ),
          _chip(
            context,
            estudo.mostrarComoEmBreve
                ? Icons.hourglass_empty_rounded
                : Icons.lock_open_rounded,
            estudo.mostrarComoEmBreve
                ? 'Marcado como em breve'
                : 'Sem bloqueio de em breve',
          ),
        ],
      ),
    );
  }

  Widget _callout(
    BuildContext context,
    IconData icon,
    String label,
    String text,
  ) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(t.primary.withValues(alpha: 0.08), t.card),
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: t.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: t.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: TextStyle(
                    color: t.textPrimary,
                    height: 1.35,
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

  Widget _chip(BuildContext context, IconData icon, String label) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: t.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: t.textSecondary, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(BuildContext context) {
    final t = context.uai;
    final color = switch (estudo.status) {
      EstudoCicloStatus.publicado => t.success,
      EstudoCicloStatus.emBreve => t.info,
      EstudoCicloStatus.oculto => t.textMuted,
      EstudoCicloStatus.arquivado => t.error,
      _ => t.warning,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.10), t.card),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        EstudoCicloStatus.label(estudo.status),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _textPill(BuildContext context, String text) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: t.border),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: t.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
