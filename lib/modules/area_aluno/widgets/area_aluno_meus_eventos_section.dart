// lib/modules/area_aluno/widgets/area_aluno_meus_eventos_section.dart
//
// Seção pública da Área do Aluno para exibir eventos em andamento
// nos quais o aluno está participando.
//
// IMPORTANTE:
// - Somente leitura.
// - Não altera participação.
// - Não registra pagamento.
// - Não altera camisa.
// - Não altera certificado.
//
// AJUSTE V3:
// - Card do evento mais intuitivo visualmente.
// - Se estiver pago/quitado: fundo com efeito suave verde.
// - Se estiver pendente: fundo com efeito suave vermelho.
// - Se estiver parcial: fundo com efeito suave amarelo.
// - Mantém logo real do evento, status e tipo de pagamento/patrocínio.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/area_aluno/services/area_aluno_eventos_service.dart';

class AreaAlunoMeusEventosSection extends StatefulWidget {
  final Map<String, dynamic> aluno;
  final Map<String, dynamic> authPayload;
  final ValueChanged<AreaAlunoEventoResumo>? onAbrirEvento;

  const AreaAlunoMeusEventosSection({
    super.key,
    required this.aluno,
    required this.authPayload,
    this.onAbrirEvento,
  });

  @override
  State<AreaAlunoMeusEventosSection> createState() =>
      _AreaAlunoMeusEventosSectionState();
}

class _AreaAlunoMeusEventosSectionState
    extends State<AreaAlunoMeusEventosSection> {
  final AreaAlunoEventosService _service = AreaAlunoEventosService();
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');

  late Future<List<AreaAlunoEventoResumo>> _future;

  @override
  void initState() {
    super.initState();
    _future = _carregarEventos();
  }

  @override
  void didUpdateWidget(covariant AreaAlunoMeusEventosSection oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.aluno != widget.aluno ||
        oldWidget.authPayload != widget.authPayload) {
      _future = _carregarEventos();
    }
  }

  Future<List<AreaAlunoEventoResumo>> _carregarEventos() {
    return _service.listarEventosEmAndamentoDoAluno(
      aluno: widget.aluno,
      authPayload: widget.authPayload,
    );
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

  String _formatMoney(double value) {
    return NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
    ).format(value);
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Data não informada';
    return _dateFormat.format(date);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AreaAlunoEventoResumo>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingCard();
        }

        final eventos = snapshot.data ?? [];

        if (eventos.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(eventos.length),
            const SizedBox(height: 10),
            ...eventos.map((evento) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildEventoSlimCard(evento),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildLoadingCard() {
    final t = context.uai;
    final accent = _ensureVisible(t.primary, t.card);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Verificando eventos em andamento...',
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(int total) {
    final t = context.uai;
    final accent = _ensureVisible(t.primary, t.background);

    return Row(
      children: [
        Container(
          width: 39,
          height: 39,
          decoration: BoxDecoration(
            color: Color.alphaBlend(accent.withOpacity(0.09), t.cardAlt),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(Icons.event_available_rounded, color: accent, size: 21),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                total == 1 ? 'Meu evento' : 'Meus eventos',
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                total == 1
                    ? 'Evento em andamento vinculado ao seu cadastro'
                    : '$total eventos em andamento vinculados ao seu cadastro',
                style: TextStyle(
                  color: t.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEventoSlimCard(AreaAlunoEventoResumo evento) {
    final t = context.uai;
    final pagamentoAccent = _ensureVisible(_pagamentoColor(evento), t.card);
    final origemAccent =
    _ensureVisible(_origemPagamentoColor(evento), t.card);
    final cardBg = _cardBackgroundColor(evento);
    final onCardBg = _readableOn(cardBg);

    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _abrirEvento(evento),
        borderRadius: BorderRadius.circular(22),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: pagamentoAccent.withOpacity(0.20)),
            boxShadow: t.softShadow,
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: pagamentoAccent,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(22),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        _buildEventoLogo(evento, pagamentoAccent, cardBg),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      evento.nomeEvento,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: t.textPrimary,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 13.8,
                                        height: 1.1,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  _buildPagamentoStatusPill(
                                    evento,
                                    pagamentoAccent,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  Icon(
                                    _pagamentoIcon(evento),
                                    color: pagamentoAccent,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      _pagamentoResumo(evento),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: pagamentoAccent,
                                        fontSize: 11.2,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 7),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  _buildMiniChip(
                                    icon: Icons.calendar_month_rounded,
                                    label: _formatDate(evento.dataEvento),
                                    color: t.primary,
                                    background: cardBg,
                                  ),
                                  _buildMiniChip(
                                    icon: evento.possuiPatrocinio
                                        ? Icons.volunteer_activism_rounded
                                        : Icons.payments_rounded,
                                    label: evento.origemPagamentoLabel,
                                    color: origemAccent,
                                    background: cardBg,
                                  ),
                                  if (evento.temCamisa)
                                    _buildMiniChip(
                                      icon: Icons.checkroom_rounded,
                                      label: evento.tamanhoCamisa,
                                      color: t.warning,
                                      background: cardBg,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: onCardBg.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: pagamentoAccent.withOpacity(0.12),
                            ),
                          ),
                          child: Icon(
                            Icons.chevron_right_rounded,
                            color: pagamentoAccent,
                            size: 24,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _cardBackgroundColor(AreaAlunoEventoResumo evento) {
    final t = context.uai;
    final accent = _ensureVisible(_pagamentoColor(evento), t.card);

    final opacity = evento.pagamentoQuitado
        ? 0.085
        : evento.pagamentoParcial
        ? 0.080
        : 0.090;

    return Color.alphaBlend(accent.withOpacity(opacity), t.card);
  }

  Widget _buildEventoLogo(
      AreaAlunoEventoResumo evento,
      Color accent,
      Color background,
      ) {
    final t = context.uai;
    final logo = evento.logoEventoUrl.trim();

    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.10), background),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(0.13)),
      ),
      child: logo.isNotEmpty
          ? ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: Image.network(
          logo,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildEventoLogoFallback(accent),
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: accent,
                ),
              ),
            );
          },
        ),
      )
          : _buildEventoLogoFallback(accent),
    );
  }

  Widget _buildEventoLogoFallback(Color accent) {
    return Icon(
      Icons.emoji_events_rounded,
      color: accent,
      size: 30,
    );
  }

  Widget _buildPagamentoStatusPill(
      AreaAlunoEventoResumo evento,
      Color pagamentoAccent,
      ) {
    final t = context.uai;
    final label = evento.statusPagamentoLabel.toUpperCase();
    final fg = evento.pagamentoQuitado || !evento.pagamentoParcial
        ? _readableOn(pagamentoAccent)
        : pagamentoAccent;

    final bg = evento.pagamentoParcial
        ? Color.alphaBlend(pagamentoAccent.withOpacity(0.12), t.cardAlt)
        : pagamentoAccent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: pagamentoAccent.withOpacity(0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_pagamentoIcon(evento), color: fg, size: 11.5),
          const SizedBox(width: 3.5),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 9.8,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  IconData _pagamentoIcon(AreaAlunoEventoResumo evento) {
    if (evento.valorTotal <= 0) return Icons.info_rounded;
    if (evento.pagamentoQuitado) return Icons.check_circle_rounded;
    if (evento.pagamentoParcial) return Icons.timelapse_rounded;
    return Icons.error_rounded;
  }

  String _pagamentoResumo(AreaAlunoEventoResumo evento) {
    if (evento.valorTotal <= 0) {
      return 'Evento sem cobrança registrada';
    }

    if (evento.pagamentoQuitado) {
      return 'Pagamento confirmado';
    }

    if (evento.pagamentoParcial) {
      return 'Parcial • falta ${_formatMoney(evento.saldo)}';
    }

    return 'Pendente • saldo ${_formatMoney(evento.saldo)}';
  }

  Widget _buildMiniChip({
    required IconData icon,
    required String label,
    required Color color,
    required Color background,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, background);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.08), background),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 12.5),
          const SizedBox(width: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Color _pagamentoColor(AreaAlunoEventoResumo evento) {
    final t = context.uai;

    if (evento.valorTotal <= 0) return t.info;
    if (evento.pagamentoQuitado) return t.success;
    if (evento.pagamentoParcial) return t.warning;
    return t.error;
  }

  Color _origemPagamentoColor(AreaAlunoEventoResumo evento) {
    final t = context.uai;

    if (evento.possuiPatrocinio && evento.totalPagoDireto > 0.01) {
      return t.associacao;
    }

    if (evento.possuiPatrocinio) return t.info;

    return t.primary;
  }

  void _abrirEvento(AreaAlunoEventoResumo evento) {
    if (widget.onAbrirEvento != null) {
      widget.onAbrirEvento!(evento);
      return;
    }

    _mostrarDetalhesRapidos(evento);
  }

  void _mostrarDetalhesRapidos(AreaAlunoEventoResumo evento) {
    final t = context.uai;
    final accent = _ensureVisible(_pagamentoColor(evento), t.surface);
    final cardBg = Color.alphaBlend(accent.withOpacity(0.07), t.surface);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width > 760
            ? 720
            : MediaQuery.of(context).size.width,
      ),
      builder: (_) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: t.border),
              boxShadow: t.cardShadow,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: t.border,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _buildEventoLogo(evento, accent, cardBg),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              evento.nomeEvento,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: t.textPrimary,
                                fontSize: 18,
                                height: 1.12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Resumo somente leitura',
                              style: TextStyle(
                                color: t.textSecondary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close_rounded, color: t.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _buildSheetRow('Evento', evento.nomeEvento),
                  _buildSheetRow('Data', _formatDate(evento.dataEvento)),
                  _buildSheetRow(
                    'Local',
                    evento.local.isEmpty ? 'Não informado' : evento.local,
                  ),
                  _buildSheetRow('Camisa', evento.camisaLabel),
                  _buildSheetRow('Tipo', evento.origemPagamentoLabel),
                  _buildSheetRow('Pagamento', evento.statusPagamentoLabel),
                  if (evento.totalPatrocinado > 0)
                    _buildSheetRow(
                      'Patrocínio',
                      _formatMoney(evento.totalPatrocinado),
                    ),
                  if (evento.totalPagoDireto > 0)
                    _buildSheetRow(
                      'Pago direto',
                      _formatMoney(evento.totalPagoDireto),
                    ),
                  _buildSheetRow('Total', _formatMoney(evento.valorTotal)),
                  _buildSheetRow('Valor pago', _formatMoney(evento.totalPago)),
                  _buildSheetRow('Saldo devedor', _formatMoney(evento.saldo)),
                  _buildSheetRow('Certificado', evento.certificadoLabel),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(
                        accent.withOpacity(0.07),
                        t.card,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: accent.withOpacity(0.13)),
                    ),
                    child: Text(
                      'Para corrigir camisa, nome, graduação ou qualquer dado do evento, use o card “Solicitar alterações” na Área do Aluno.',
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSheetRow(String label, String value) {
    final t = context.uai;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.trim().isEmpty ? 'Não informado' : value,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
