import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudo_ciclo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/widgets/estudo_artigo_renderer.dart';

class PreviewEstudoScreen extends StatelessWidget {
  final EstudoModel estudo;

  const PreviewEstudoScreen({super.key, required this.estudo});

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(title: const Text('Pre-visualizacao do estudo')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                _adminNotice(context),
                const SizedBox(height: 12),
                _editorialChecklist(context),
                const SizedBox(height: 12),
                EstudoArtigoRenderer(estudo: estudo),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _adminNotice(BuildContext context) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(t.warning.withValues(alpha: 0.12), t.card),
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        border: Border.all(color: t.warning.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.admin_panel_settings_rounded, color: t.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pre-visualizacao administrativa',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Este conteudo pode estar em rascunho e ainda nao representa uma liberacao para alunos.',
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

  Widget _editorialChecklist(BuildContext context) {
    final t = context.uai;
    final items = <_ChecklistItem>[
      _ChecklistItem('Possui ciclo', estudo.cicloId.isNotEmpty),
      _ChecklistItem('Possui titulo', estudo.titulo.trim().isNotEmpty),
      _ChecklistItem('Possui numero', estudo.numero > 0),
      _ChecklistItem('Possui resumo', estudo.resumo.trim().isNotEmpty),
      _ChecklistItem(
        'Possui texto aprofundado',
        estudo.textoAprofundado.trim().isNotEmpty,
      ),
      _ChecklistItem(
        'Possui pergunta principal',
        estudo.perguntaPrincipal.trim().isNotEmpty,
      ),
      _ChecklistItem(
        'Possui reflexao final',
        estudo.reflexaoFinal.trim().isNotEmpty,
      ),
      _ChecklistItem('Possui fontes', estudo.fontesLista.isNotEmpty),
      _ChecklistItem(
        'Possui video',
        estudo.videoYoutubeUrl.trim().isNotEmpty,
        optional: true,
      ),
      _ChecklistItem(
        'Esta publicado',
        estudo.status == EstudoCicloStatus.publicado,
      ),
      _ChecklistItem('Aparece na linha do tempo', estudo.mostrarNaLinhaDoTempo),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
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
              Icon(Icons.checklist_rounded, color: t.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Checklist editorial',
                  style: TextStyle(
                    color: t.textPrimary,
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
            children: items.map((item) => _checkChip(context, item)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _checkChip(BuildContext context, _ChecklistItem item) {
    final t = context.uai;
    final color = item.ok
        ? t.success
        : (item.optional ? t.textMuted : t.warning);
    final icon = item.ok
        ? Icons.check_circle_rounded
        : (item.optional
              ? Icons.radio_button_unchecked_rounded
              : Icons.warning_amber_rounded);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.10), t.card),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 5),
          Text(
            item.label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChecklistItem {
  final String label;
  final bool ok;
  final bool optional;

  const _ChecklistItem(this.label, this.ok, {this.optional = false});
}
