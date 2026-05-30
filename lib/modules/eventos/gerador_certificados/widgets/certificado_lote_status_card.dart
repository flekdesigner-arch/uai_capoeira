import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';

class CertificadoLoteStatusCard extends StatelessWidget {
  final int totalParticipantes;
  final int selecionados;
  final int gerados;
  final int impressos;
  final int pendentes;
  final int comErro;
  final int incluidosZip;
  final bool carregando;
  final String? mensagem;

  const CertificadoLoteStatusCard({
    super.key,
    required this.totalParticipantes,
    required this.selecionados,
    required this.gerados,
    required this.impressos,
    required this.pendentes,
    required this.comErro,
    required this.incluidosZip,
    this.carregando = false,
    this.mensagem,
  });

  double get _percentualGerados {
    if (totalParticipantes <= 0) return 0;
    return (gerados / totalParticipantes).clamp(0.0, 1.0);
  }

  double get _percentualImpressos {
    if (totalParticipantes <= 0) return 0;
    return (impressos / totalParticipantes).clamp(0.0, 1.0);
  }

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
    final primary = _ensureVisible(t.primary, t.card);
    final onPrimary = _readableOn(primary);

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(t.cardRadius),
          border: Border.all(color: t.border),
          boxShadow: t.softShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: t.primaryGradient,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 520;

                  final icon = Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: onPrimary.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(t.buttonRadius),
                      border: Border.all(color: onPrimary.withOpacity(0.16)),
                    ),
                    child: carregando
                        ? Padding(
                      padding: const EdgeInsets.all(13),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: onPrimary,
                      ),
                    )
                        : Icon(
                      Icons.workspace_premium_rounded,
                      color: onPrimary,
                      size: 29,
                    ),
                  );

                  final text = Column(
                    crossAxisAlignment: narrow
                        ? CrossAxisAlignment.center
                        : CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Controle de certificados',
                        textAlign: narrow ? TextAlign.center : TextAlign.left,
                        style: TextStyle(
                          color: onPrimary,
                          fontSize: narrow ? 19 : 21,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        mensagem ??
                            'Gere, imprima, acompanhe lotes e prepare pacote para gráfica.',
                        textAlign: narrow ? TextAlign.center : TextAlign.left,
                        style: TextStyle(
                          color: onPrimary.withOpacity(0.82),
                          fontSize: 12.4,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  );

                  if (narrow) {
                    return Column(
                      children: [
                        icon,
                        const SizedBox(height: 12),
                        text,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      icon,
                      const SizedBox(width: 13),
                      Expanded(child: text),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final narrow = constraints.maxWidth < 680;

                      final cards = [
                        _StatusMiniCard(
                          icon: Icons.groups_rounded,
                          label: 'Total',
                          value: totalParticipantes.toString(),
                          color: t.info,
                        ),
                        _StatusMiniCard(
                          icon: Icons.checklist_rounded,
                          label: 'Selecionados',
                          value: selecionados.toString(),
                          color: primary,
                        ),
                        _StatusMiniCard(
                          icon: Icons.picture_as_pdf_rounded,
                          label: 'Gerados',
                          value: gerados.toString(),
                          color: t.success,
                        ),
                        _StatusMiniCard(
                          icon: Icons.print_rounded,
                          label: 'Impressos',
                          value: impressos.toString(),
                          color: t.associacao,
                        ),
                        _StatusMiniCard(
                          icon: Icons.hourglass_empty_rounded,
                          label: 'Pendentes',
                          value: pendentes.toString(),
                          color: t.warning,
                        ),
                        _StatusMiniCard(
                          icon: Icons.inventory_2_rounded,
                          label: 'No ZIP',
                          value: incluidosZip.toString(),
                          color: t.info,
                        ),
                        if (comErro > 0)
                          _StatusMiniCard(
                            icon: Icons.error_rounded,
                            label: 'Erros',
                            value: comErro.toString(),
                            color: t.error,
                          ),
                      ];

                      if (narrow) {
                        return Wrap(
                          spacing: 9,
                          runSpacing: 9,
                          children: cards
                              .map(
                                (card) => SizedBox(
                              width:
                              (constraints.maxWidth - 9) / 2 < 160
                                  ? constraints.maxWidth
                                  : (constraints.maxWidth - 9) / 2,
                              child: card,
                            ),
                          )
                              .toList(),
                        );
                      }

                      return Wrap(
                        spacing: 9,
                        runSpacing: 9,
                        children: cards
                            .map(
                              (card) => SizedBox(
                            width: 145,
                            child: card,
                          ),
                        )
                            .toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  _ProgressLine(
                    label: 'Certificados gerados',
                    value: _percentualGerados,
                    current: gerados,
                    total: totalParticipantes,
                    color: t.success,
                  ),
                  const SizedBox(height: 10),
                  _ProgressLine(
                    label: 'Certificados impressos',
                    value: _percentualImpressos,
                    current: impressos,
                    total: totalParticipantes,
                    color: t.associacao,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusMiniCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatusMiniCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

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
    final accent = _ensureVisible(color, t.cardAlt);

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.08), t.cardAlt),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withOpacity(0.16)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.11),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: accent, size: 19),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 10.8,
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
}

class _ProgressLine extends StatelessWidget {
  final String label;
  final double value;
  final int current;
  final int total;
  final Color color;

  const _ProgressLine({
    required this.label,
    required this.value,
    required this.current,
    required this.total,
    required this.color,
  });

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
    final accent = _ensureVisible(color, t.card);
    final percent = (value * 100).clamp(0, 100).toStringAsFixed(0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 12.2,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Text(
              '$current/$total • $percent%',
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 9,
            color: accent,
            backgroundColor: t.border.withOpacity(0.35),
          ),
        ),
      ],
    );
  }
}
