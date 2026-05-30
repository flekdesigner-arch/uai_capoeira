import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';

enum CertificadoFiltroParticipantes {
  todos,
  quitados,
  presentes,
  semCertificado,
  comCertificado,
  naoImpressos,
}

extension CertificadoFiltroParticipantesX on CertificadoFiltroParticipantes {
  String get label {
    switch (this) {
      case CertificadoFiltroParticipantes.todos:
        return 'Todos';
      case CertificadoFiltroParticipantes.quitados:
        return 'Quitados';
      case CertificadoFiltroParticipantes.presentes:
        return 'Presentes';
      case CertificadoFiltroParticipantes.semCertificado:
        return 'Sem certificado';
      case CertificadoFiltroParticipantes.comCertificado:
        return 'Com certificado';
      case CertificadoFiltroParticipantes.naoImpressos:
        return 'Não impressos';
    }
  }

  IconData get icon {
    switch (this) {
      case CertificadoFiltroParticipantes.todos:
        return Icons.groups_rounded;
      case CertificadoFiltroParticipantes.quitados:
        return Icons.payments_rounded;
      case CertificadoFiltroParticipantes.presentes:
        return Icons.check_circle_rounded;
      case CertificadoFiltroParticipantes.semCertificado:
        return Icons.hourglass_empty_rounded;
      case CertificadoFiltroParticipantes.comCertificado:
        return Icons.verified_rounded;
      case CertificadoFiltroParticipantes.naoImpressos:
        return Icons.print_disabled_rounded;
    }
  }
}

class CertificadoEventoToolbar extends StatelessWidget {
  final CertificadoFiltroParticipantes filtro;
  final ValueChanged<CertificadoFiltroParticipantes> onFiltroChanged;
  final String busca;
  final ValueChanged<String> onBuscaChanged;
  final int total;
  final int selecionados;
  final bool todosSelecionados;
  final bool carregando;
  final VoidCallback? onRecarregar;
  final VoidCallback? onSelecionarTodos;
  final VoidCallback? onLimparSelecao;
  final VoidCallback? onGerarSelecionados;
  final VoidCallback? onCriarLotesImpressao;
  final VoidCallback? onGerarRelatorioGrafica;
  final VoidCallback? onCriarPacoteGrafica;

  const CertificadoEventoToolbar({
    super.key,
    required this.filtro,
    required this.onFiltroChanged,
    required this.busca,
    required this.onBuscaChanged,
    required this.total,
    required this.selecionados,
    required this.todosSelecionados,
    this.carregando = false,
    this.onRecarregar,
    this.onSelecionarTodos,
    this.onLimparSelecao,
    this.onGerarSelecionados,
    this.onCriarLotesImpressao,
    this.onGerarRelatorioGrafica,
    this.onCriarPacoteGrafica,
  });

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff =
    (color.computeLuminance() - background.computeLuminance()).abs();

    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(t.cardRadius),
          border: Border.all(color: t.border),
          boxShadow: t.softShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            const SizedBox(height: 12),
            _buildSearch(context),
            const SizedBox(height: 12),
            _buildFilters(context),
            const SizedBox(height: 12),
            _buildActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.card);

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 560;

        final title = Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: primary.withOpacity(0.11),
                borderRadius: BorderRadius.circular(t.buttonRadius),
                border: Border.all(color: primary.withOpacity(0.14)),
              ),
              child: carregando
                  ? Padding(
                padding: const EdgeInsets.all(11),
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: primary,
                ),
              )
                  : Icon(Icons.tune_rounded, color: primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment:
                narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ferramentas do gerador',
                    textAlign: narrow ? TextAlign.center : TextAlign.left,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$total participante(s) • $selecionados selecionado(s)',
                    textAlign: narrow ? TextAlign.center : TextAlign.left,
                    style: TextStyle(
                      color: t.textSecondary,
                      fontSize: 11.7,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

        final reload = OutlinedButton.icon(
          onPressed: carregando ? null : onRecarregar,
          icon: const Icon(Icons.refresh_rounded, size: 17),
          label: const Text('Atualizar'),
          style: OutlinedButton.styleFrom(
            foregroundColor: primary,
            disabledForegroundColor: t.textMuted,
            side: BorderSide(color: primary.withOpacity(0.22)),
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(t.buttonRadius),
            ),
          ),
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: 10),
              reload,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: title),
            const SizedBox(width: 10),
            reload,
          ],
        );
      },
    );
  }

  Widget _buildSearch(BuildContext context) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.cardAlt);

    return TextField(
      onChanged: onBuscaChanged,
      controller: TextEditingController(text: busca)
        ..selection = TextSelection.collapsed(offset: busca.length),
      style: TextStyle(color: t.textPrimary),
      decoration: InputDecoration(
        labelText: 'Buscar participante',
        hintText: 'Digite nome, graduação ou status...',
        labelStyle: TextStyle(color: t.textSecondary),
        hintStyle: TextStyle(color: t.textMuted),
        prefixIcon: Icon(Icons.search_rounded, color: primary),
        suffixIcon: busca.trim().isEmpty
            ? null
            : IconButton(
          onPressed: () => onBuscaChanged(''),
          icon: Icon(Icons.close_rounded, color: t.textSecondary),
        ),
        filled: true,
        fillColor: t.cardAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
          borderSide: BorderSide(color: t.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
          borderSide: BorderSide(color: t.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
          borderSide: BorderSide(color: primary, width: 1.4),
        ),
      ),
    );
  }

  Widget _buildFilters(BuildContext context) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.card);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: CertificadoFiltroParticipantes.values.map((item) {
        final selected = item == filtro;

        return ChoiceChip(
          selected: selected,
          label: Text(item.label),
          avatar: Icon(
            item.icon,
            size: 16,
            color: selected ? _readableOn(primary) : primary,
          ),
          selectedColor: primary,
          backgroundColor: t.cardAlt,
          labelStyle: TextStyle(
            color: selected ? _readableOn(primary) : t.textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 11.5,
          ),
          side: BorderSide(
            color: selected ? primary.withOpacity(0.28) : t.border,
          ),
          onSelected: (_) => onFiltroChanged(item),
          visualDensity: VisualDensity.compact,
        );
      }).toList(),
    );
  }

  Widget _buildActions(BuildContext context) {
    final t = context.uai;

    return LayoutBuilder(
      builder: (context, constraints) {
        final buttonWidth = constraints.maxWidth < 620
            ? constraints.maxWidth
            : constraints.maxWidth < 920
            ? (constraints.maxWidth - 10) / 2
            : (constraints.maxWidth - 20) / 3;

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: buttonWidth,
              child: _actionButton(
                context,
                icon: todosSelecionados
                    ? Icons.deselect_rounded
                    : Icons.select_all_rounded,
                label: todosSelecionados
                    ? 'Limpar seleção'
                    : 'Selecionar filtrados',
                color: t.info,
                onTap: carregando
                    ? null
                    : todosSelecionados
                    ? onLimparSelecao
                    : onSelecionarTodos,
                filled: false,
              ),
            ),
            SizedBox(
              width: buttonWidth,
              child: _actionButton(
                context,
                icon: Icons.workspace_premium_rounded,
                label: 'Gerar selecionados',
                color: t.success,
                onTap: selecionados <= 0 || carregando
                    ? null
                    : onGerarSelecionados,
                filled: true,
              ),
            ),
            SizedBox(
              width: buttonWidth,
              child: _actionButton(
                context,
                icon: Icons.print_rounded,
                label: 'Lotes impressão',
                color: t.associacao,
                onTap: selecionados <= 0 || carregando
                    ? null
                    : onCriarLotesImpressao,
                filled: false,
              ),
            ),
            SizedBox(
              width: buttonWidth,
              child: _actionButton(
                context,
                icon: Icons.assignment_rounded,
                label: 'Relatório gráfica',
                color: t.info,
                onTap: selecionados <= 0 || carregando
                    ? null
                    : onGerarRelatorioGrafica,
                filled: false,
              ),
            ),
            SizedBox(
              width: buttonWidth,
              child: _actionButton(
                context,
                icon: Icons.inventory_2_rounded,
                label: 'ZIP gráfica',
                color: t.warning,
                onTap: selecionados <= 0 || carregando
                    ? null
                    : onCriarPacoteGrafica,
                filled: false,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _actionButton(
      BuildContext context, {
        required IconData icon,
        required String label,
        required Color color,
        required VoidCallback? onTap,
        required bool filled,
      }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);
    final onAccent = _readableOn(accent);

    if (filled) {
      return ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          disabledBackgroundColor: t.cardAlt,
          disabledForegroundColor: t.textMuted,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.buttonRadius),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 12.2,
          ),
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: accent,
        disabledForegroundColor: t.textMuted,
        side: BorderSide(
          color: onTap == null ? t.border : accent.withOpacity(0.28),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.buttonRadius),
        ),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 12.2,
        ),
      ),
    );
  }
}
