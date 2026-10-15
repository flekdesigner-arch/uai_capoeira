import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/models/certificado_evento_data.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/models/certificado_participante_data.dart';

class CertificadoParticipanteCard extends StatelessWidget {
  final CertificadoEventoData evento;
  final CertificadoParticipanteData participante;
  final bool selecionado;
  final bool processando;
  final bool compacto;
  final ValueChanged<bool>? onSelecionar;
  final VoidCallback? onUploadPdf;
  final VoidCallback? onPreview;
  final VoidCallback? onGerarPdf;
  final VoidCallback? onGerarPng;
  final VoidCallback? onImprimir;
  final VoidCallback? onCompartilhar;
  final VoidCallback? onMarcarImpresso;
  final VoidCallback? onEmitirV2;
  final VoidCallback? onAbrirValidador;
  final VoidCallback? onCopiarLink;

  const CertificadoParticipanteCard({
    super.key,
    required this.evento,
    required this.participante,
    required this.selecionado,
    this.processando = false,
    this.compacto = false,
    this.onSelecionar,
    this.onUploadPdf,
    this.onPreview,
    this.onGerarPdf,
    this.onGerarPng,
    this.onImprimir,
    this.onCompartilhar,
    this.onMarcarImpresso,
    this.onEmitirV2,
    this.onAbrirValidador,
    this.onCopiarLink,
  });

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

  Color _hexToColor(String hex, {Color fallback = const Color(0xFF9E9E9E)}) {
    try {
      final clean = hex.replaceAll('#', '').trim();

      if (clean.length == 6) {
        return Color(int.parse('FF$clean', radix: 16));
      }

      if (clean.length == 8) {
        return Color(int.parse(clean, radix: 16));
      }
    } catch (_) {}

    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    final template = participante.tipoTemplate(evento);
    final templateLabel = participante.pdfImportado ? 'PDF importado' : evento.exigePdfIndividual ? 'PDF individual' : _templateLabel(template);
    final accent = _ensureVisible(_hexToColor(participante.cor1), t.card);
    final borderColor = selecionado
        ? accent.withAlpha(97)
        : participante.temCertificadoGerado
        ? _ensureVisible(t.success, t.card).withAlpha(61)
        : t.border;

    return Material(
      color: selecionado
          ? Color.alphaBlend(accent.withAlpha(20), t.card)
          : t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPreview,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(
              color: borderColor,
              width: selecionado ? 1.4 : 1,
            ),
            boxShadow: t.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTop(context, accent, templateLabel),
              if (!compacto) ...[
                const SizedBox(height: 10),
                _buildInfoChips(context),
              ],
              const SizedBox(height: 10),
              _buildStatusRow(context),
              const SizedBox(height: 10),
              _buildActions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTop(BuildContext context, Color accent, String templateNome) {
    final t = context.uai;
    final onAccent = _readableOn(accent);

    return Row(
      children: [
        Checkbox(
          value: selecionado,
          activeColor: accent,
          onChanged: onSelecionar == null
              ? null
              : (value) => onSelecionar!(value ?? false),
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 4),
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(t.buttonRadius),
            boxShadow: [
              BoxShadow(
                color: accent.withAlpha(46),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Text(
              _iniciais(participante.alunoNome),
              style: TextStyle(
                color: onAccent,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                participante.alunoNome,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 14.6,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                participante.graduacaoNova.isEmpty
                    ? 'Graduação não informada'
                    : participante.graduacaoNova,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.textSecondary,
                  fontSize: 11.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                templateNome,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: accent,
                  fontSize: 11.2,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        if (processando) ...[
          const SizedBox(width: 8),
          SizedBox(
            width: 21,
            height: 21,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: accent),
          ),
        ] else ...[
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, color: t.textMuted),
        ],
      ],
    );
  }

  Widget _buildInfoChips(BuildContext context) {
    final t = context.uai;

    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        _chip(
          context,
          icon: Icons.payments_rounded,
          label: participante.estaQuitado ? 'Quitado' : 'Pendente',
          color: participante.estaQuitado ? t.success : t.warning,
        ),
        _chip(
          context,
          icon: Icons.check_circle_rounded,
          label: participante.presente ? 'Presente' : 'Ausente',
          color: participante.presente ? t.success : t.textMuted,
        ),
        _chip(
          context,
          icon: Icons.badge_rounded,
          label: participante.temCpf ? 'CPF ok' : 'Sem CPF',
          color: participante.temCpf ? t.info : t.warning,
        ),
        _chip(
          context,
          icon: Icons.workspace_premium_rounded,
          label: participante.temGraduacaoNova
              ? 'Graduação ok'
              : 'Sem graduação',
          color: participante.temGraduacaoNova ? t.success : t.error,
        ),
      ],
    );
  }

  Widget _buildStatusRow(BuildContext context) {
    final t = context.uai;

    final oficialV2 = participante.temEmissaoOficialV2NoEvento(evento);
    final statusEvento = participante.statusEmissaoV2NoEvento(evento);
    final processandoV2 = const {'preparando', 'gerando', 'publicando'}.contains(statusEvento);
    final erroV2 = statusEvento == 'erro';
    final gerado = participante.temCertificadoGerado;
    final statusColor = _ensureVisible(
      oficialV2
          ? t.info
          : erroV2
              ? t.error
              : processandoV2
                  ? t.warning
                  : (gerado ? t.success : t.warning),
      t.card,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Color.alphaBlend(statusColor.withAlpha(20), t.cardAlt),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withAlpha(41)),
      ),
      child: Row(
        children: [
          Icon(
            oficialV2
                ? Icons.verified_user_rounded
                : erroV2
                    ? Icons.error_outline_rounded
                    : processandoV2
                        ? Icons.sync_rounded
                        : (gerado
                            ? Icons.verified_rounded
                            : Icons.hourglass_empty_rounded),
            color: statusColor,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  oficialV2
                      ? 'CERTIFICADO OFICIAL • autenticidade ativa'
                      : erroV2
                          ? 'Emissão interrompida • pode tentar novamente'
                          : processandoV2
                              ? 'Emitindo certificado oficial • ${participante.statusEmissaoV2NoEvento(evento)}'
                              : gerado
                                  ? 'PDF gerado • ainda não é certificado oficial'
                                  : 'Certificado ainda não gerado',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11.8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (oficialV2 && participante.codigoValidacaoNoEvento(evento).isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    participante.codigoValidacaoNoEvento(evento),
                    style: TextStyle(
                      color: t.textSecondary,
                      fontSize: 10.8,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (participante.certificadoAtualizadoEm != null) ...[
            const SizedBox(width: 8),
            Text(
              _dataCurta(participante.certificadoAtualizadoEm!),
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 10.6,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.card);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compactActions = constraints.maxWidth < 560;

        final officialActions = <Widget>[
          if (participante.temEmissaoOficialV2NoEvento(evento)) ...[
            _action(
              context,
              icon: Icons.open_in_new_rounded,
              label: 'Validador',
              color: t.info,
              onTap: onAbrirValidador,
            ),
            _action(
              context,
              icon: Icons.link_rounded,
              label: 'Copiar link',
              color: t.success,
              onTap: onCopiarLink,
            ),
          ] else if (onEmitirV2 != null)
            _action(
              context,
              icon: Icons.verified_user_rounded,
              label: 'Emitir V2',
              color: t.info,
              onTap: onEmitirV2,
            ),
        ];

        final actions = [
          if (onUploadPdf != null) _action(context, icon: Icons.upload_file_rounded, label: 'Enviar PDF', color: primary, onTap: onUploadPdf),
          _action(
            context,
            icon: Icons.visibility_rounded,
            label: 'Prévia',
            color: primary,
            onTap: onPreview,
          ),
          _action(
            context,
            icon: Icons.picture_as_pdf_rounded,
            label: 'PDF',
            color: t.error,
            onTap: onGerarPdf,
          ),
          if (!evento.exigePdfIndividual && !participante.pdfImportado) _action(
            context,
            icon: Icons.image_rounded,
            label: 'PNG',
            color: t.info,
            onTap: onGerarPng,
          ),
          _action(
            context,
            icon: Icons.print_rounded,
            label: 'Imprimir',
            color: t.associacao,
            onTap: onImprimir,
          ),
          _action(
            context,
            icon: Icons.share_rounded,
            label: 'Compart.',
            color: t.success,
            onTap: onCompartilhar,
          ),
          _action(
            context,
            icon: Icons.fact_check_rounded,
            label: 'Impresso',
            color: t.warning,
            onTap: onMarcarImpresso,
          ),
        ];

        if (compactActions) {
          return Wrap(spacing: 7, runSpacing: 7, children: [...officialActions, ...actions]);
        }

        return Row(
          children: [...officialActions, ...actions]
              .map(
                (item) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: item,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _action(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return SizedBox(
      height: 38,
      child: OutlinedButton.icon(
        onPressed: processando ? null : onTap,
        icon: Icon(icon, size: 15),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          disabledForegroundColor: t.textMuted,
          side: BorderSide(
            color: onTap == null ? t.border : accent.withAlpha(56),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withAlpha(20), t.cardAlt),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withAlpha(36)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: accent),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 10.7,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  String _templateLabel(dynamic template) {
    final raw = template.toString().split('.').last;

    switch (raw) {
      case 'certificadoSemCpf':
        return 'Certificado simples';
      case 'certificadoComCpf':
        return 'Certificado com CPF';
      case 'diploma':
        return 'Diploma';
      default:
        return raw
            .replaceAllMapped(
              RegExp(r'([a-z])([A-Z])'),
              (match) => '${match.group(1)} ${match.group(2)}',
            )
            .toUpperCase();
    }
  }

  String _iniciais(String nome) {
    final partes = nome
        .trim()
        .split(RegExp(r'\s+'))
        .where((parte) => parte.trim().isNotEmpty)
        .toList();

    if (partes.isEmpty) return '?';
    if (partes.length == 1) {
      return partes.first.substring(0, 1).toUpperCase();
    }

    return '${partes.first.substring(0, 1)}${partes.last.substring(0, 1)}'
        .toUpperCase();
  }

  String _dataCurta(DateTime data) {
    return '${data.day.toString().padLeft(2, '0')}/'
        '${data.month.toString().padLeft(2, '0')}/'
        '${data.year}';
  }
}
