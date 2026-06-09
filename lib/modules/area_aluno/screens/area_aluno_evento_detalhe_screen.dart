// lib/modules/area_aluno/screens/area_aluno_evento_detalhe_screen.dart
//
// Tela pública da Área do Aluno para visualizar os detalhes da participação
// do aluno em um evento em andamento.
//
// IMPORTANTE:
// - Somente leitura.
// - Não registra pagamento.
// - Não altera camisa.
// - Não altera graduação.
// - Não altera certificado.
// - O certificado abre dentro do próprio app/PWA sem botão de download.
//
// AJUSTE V3:
// - Bloco Financeiro mais visual e intuitivo.
// - "Pago" em destaque verde.
// - "Saldo devedor" em destaque vermelho.
// - Cards-resumo no topo do financeiro para leitura rápida.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:xml/xml.dart' as xml;

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/area_aluno/screens/area_aluno_certificado_viewer_screen.dart';
import 'package:uai_capoeira/modules/area_aluno/services/area_aluno_eventos_service.dart';

class AreaAlunoEventoDetalheScreen extends StatefulWidget {
  final AreaAlunoEventoResumo evento;

  const AreaAlunoEventoDetalheScreen({
    super.key,
    required this.evento,
  });

  @override
  State<AreaAlunoEventoDetalheScreen> createState() =>
      _AreaAlunoEventoDetalheScreenState();
}

class _AreaAlunoEventoDetalheScreenState
    extends State<AreaAlunoEventoDetalheScreen> {
  String? _svgContent;
  String? _cordaNovaGraduacaoSvg;

  AreaAlunoEventoResumo get evento => widget.evento;

  @override
  void initState() {
    super.initState();
    _loadCordaSvg();
  }

  Future<void> _loadCordaSvg() async {
    try {
      final content = await DefaultAssetBundle.of(context)
          .loadString('assets/images/corda.svg');

      if (!mounted) return;

      setState(() {
        _svgContent = content;
        _cordaNovaGraduacaoSvg = _montarCordaNovaGraduacaoSvg();
      });
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar corda.svg em Meu Evento: $e');
    }
  }

  String? _montarCordaNovaGraduacaoSvg() {
    if (_svgContent == null) return null;
    if (!evento.temCoresNovaGraduacao) return null;

    try {
      final document = xml.XmlDocument.parse(_svgContent!);

      void changeColor(String id, String? hexColor) {
        if (hexColor == null || hexColor.trim().isEmpty) return;

        final hex = _normalizarHex(hexColor);
        if (hex == null) return;

        final element = document.rootElement.descendants
            .whereType<xml.XmlElement>()
            .firstWhere(
              (e) => e.getAttribute('id') == id,
          orElse: () => xml.XmlElement(xml.XmlName('')),
        );

        if (element.name.local.isEmpty) return;

        final style = element.getAttribute('style') ?? '';
        final newStyle = style.contains('fill:')
            ? style.replaceAll(
          RegExp(r'fill:#[0-9a-fA-F]{6}'),
          'fill:$hex',
        )
            : 'fill:$hex;$style';

        element.setAttribute('style', newStyle);
      }

      changeColor('cor1', evento.graduacaoNovaCor1);
      changeColor('cor2', evento.graduacaoNovaCor2);
      changeColor(
        'corponta1',
        evento.graduacaoNovaPonta1.isNotEmpty
            ? evento.graduacaoNovaPonta1
            : evento.graduacaoNovaCor1,
      );
      changeColor(
        'corponta2',
        evento.graduacaoNovaPonta2.isNotEmpty
            ? evento.graduacaoNovaPonta2
            : evento.graduacaoNovaCor2,
      );

      return document.toXmlString();
    } catch (e) {
      debugPrint('⚠️ Erro ao montar corda da nova graduação: $e');
      return null;
    }
  }

  String? _normalizarHex(String value) {
    var hex = value.trim();

    if (hex.isEmpty || hex == 'null') return null;

    hex = hex.replaceAll('0x', '').replaceAll('0X', '');
    if (!hex.startsWith('#')) hex = '#$hex';

    if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) {
      return null;
    }

    return hex.toUpperCase();
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
    return DateFormat('dd/MM/yyyy').format(date);
  }

  String _safe(String value, {String fallback = 'Não informado'}) {
    final text = value.trim();
    if (text.isEmpty) return fallback;
    if (text.toLowerCase() == 'null') return fallback;
    return text;
  }

  Color _pagamentoColor(BuildContext context) {
    final t = context.uai;

    if (evento.valorTotal <= 0) return t.info;
    if (evento.pagamentoQuitado) return t.success;
    if (evento.pagamentoParcial) return t.warning;
    return t.error;
  }

  Color _origemPagamentoColor(BuildContext context) {
    final t = context.uai;

    if (evento.possuiPatrocinio && evento.totalPagoDireto > 0.01) {
      return t.associacao;
    }

    if (evento.possuiPatrocinio) return t.info;

    return t.primary;
  }

  Color _saldoColor(BuildContext context) {
    final t = context.uai;
    return evento.saldo > 0.01 ? t.error : t.success;
  }

  void _abrirCertificado() {
    if (!evento.temCertificado) {
      _mostrarAviso(
        titulo: 'Certificado',
        mensagem:
        'O certificado deste evento ainda não foi liberado pela coordenação.',
        icon: Icons.hourglass_bottom_rounded,
        color: context.uai.warning,
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AreaAlunoCertificadoViewerScreen(evento: evento),
      ),
    );
  }

  void _mostrarAviso({
    required String titulo,
    required String mensagem,
    required IconData icon,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.surface);

    showDialog<void>(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: t.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.cardRadius),
          ),
          title: Row(
            children: [
              Icon(icon, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            mensagem,
            style: TextStyle(color: t.textSecondary, height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'ENTENDI',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final appBarBg = Theme.of(context).appBarTheme.backgroundColor ?? t.primary;
    final appBarFg = _readableOn(appBarBg);

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text(
          'Meu evento',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
        backgroundColor: appBarBg,
        foregroundColor: appBarFg,
        iconTheme: IconThemeData(color: appBarFg),
        elevation: 0,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth =
          constraints.maxWidth > 920 ? 920.0 : constraints.maxWidth;
          final isMobile = constraints.maxWidth < 650;

          return RefreshIndicator(
            color: t.primary,
            backgroundColor: t.surface,
            onRefresh: () async => _loadCordaSvg(),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    isMobile ? 14 : 24,
                    14,
                    isMobile ? 14 : 24,
                    28,
                  ),
                  children: [
                    _buildHeroHeader(context, isMobile: isMobile),
                    const SizedBox(height: 12),
                    _buildMiniResumoEvento(context),
                    const SizedBox(height: 14),
                    _buildFinanceiroResumo(context),
                    const SizedBox(height: 14),
                    _buildGraduacaoNovaCard(context),
                    const SizedBox(height: 14),
                    _buildSection(
                      context,
                      icon: Icons.event_available_rounded,
                      title: 'Informações do evento',
                      color: t.primary,
                      children: [
                        _buildInfoRow(context, 'Evento', evento.nomeEvento),
                        _buildInfoRow(context, 'Tipo', evento.tipoEvento),
                        _buildInfoRow(
                          context,
                          'Data',
                          _formatDate(evento.dataEvento),
                        ),
                        _buildInfoRow(context, 'Cidade', _safe(evento.cidade)),
                        _buildInfoRow(context, 'Local', _safe(evento.local)),
                        _buildInfoRow(
                          context,
                          'Status',
                          _safe(evento.statusEvento),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildSection(
                      context,
                      icon: Icons.how_to_reg_rounded,
                      title: 'Minha participação',
                      color: t.success,
                      children: [
                        _buildInfoRow(
                          context,
                          'Participação',
                          _safe(
                            evento.statusParticipacao,
                            fallback: 'Participando',
                          ),
                        ),
                        _buildInfoRow(
                          context,
                          'Graduação atual',
                          _safe(evento.graduacaoAtual),
                        ),
                        _buildInfoRow(
                          context,
                          'Nova graduação',
                          _safe(
                            evento.graduacaoNova,
                            fallback: 'Não definida',
                          ),
                        ),
                        _buildInfoRow(context, 'Camisa', evento.camisaLabel),
                        _buildInfoRow(
                          context,
                          'Camisa entregue',
                          evento.camisaEntregue ? 'Sim' : 'Ainda não',
                        ),
                        _buildInfoRow(
                          context,
                          'Presença',
                          evento.presente ? 'Confirmada' : 'Ainda não marcada',
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildSection(
                      context,
                      icon: Icons.payments_rounded,
                      title: 'Financeiro',
                      color: _pagamentoColor(context),
                      children: [
                        _buildFinanceiroInfoRow(
                          context,
                          'Status',
                          evento.statusPagamentoLabel,
                          accent: _pagamentoColor(context),
                        ),
                        _buildFinanceiroInfoRow(
                          context,
                          'Tipo',
                          evento.origemPagamentoLabel,
                          accent: _origemPagamentoColor(context),
                        ),
                        _buildFinanceiroInfoRow(
                          context,
                          'Inscrição',
                          _formatMoney(evento.valorInscricao),
                          accent: t.primary,
                        ),
                        _buildFinanceiroInfoRow(
                          context,
                          'Camisa',
                          _formatMoney(evento.valorCamisa),
                          accent: t.warning,
                        ),
                        _buildFinanceiroInfoRow(
                          context,
                          'Total',
                          _formatMoney(evento.valorTotal),
                          accent: t.primary,
                          emphasize: true,
                        ),
                        _buildFinanceiroInfoRow(
                          context,
                          'Valor pago',
                          _formatMoney(evento.totalPago),
                          accent: t.success,
                          emphasize: true,
                        ),
                        if (evento.possuiPatrocinio)
                          _buildFinanceiroInfoRow(
                            context,
                            'Patrocínio',
                            _formatMoney(evento.totalPatrocinado),
                            accent: t.info,
                            emphasize: true,
                          ),
                        _buildFinanceiroInfoRow(
                          context,
                          'Saldo devedor',
                          _formatMoney(evento.saldo),
                          accent: _saldoColor(context),
                          emphasize: true,
                        ),
                        if (evento.saldo > 0.01) ...[
                          const SizedBox(height: 4),
                          _buildReadonlyNotice(
                            context,
                            icon: Icons.info_outline_rounded,
                            color: t.info,
                            text:
                            'O pagamento online ainda não está liberado nesta tela. '
                                'Por enquanto, a coordenação registra os pagamentos no sistema.',
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildCertificadoSection(context),
                    const SizedBox(height: 14),
                    _buildReadonlyNotice(
                      context,
                      icon: Icons.lock_outline_rounded,
                      color: t.info,
                      text:
                      'Esta tela é somente leitura. Para corrigir nome, camisa, graduação ou qualquer informação do evento, volte para a Área do Aluno e use o card “Solicitar alterações”.',
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeroHeader(BuildContext context, {required bool isMobile}) {
    final t = context.uai;
    final accent = _ensureVisible(t.primary, t.background);
    final onAccent = _readableOn(accent);

    return Container(
      padding: EdgeInsets.all(isMobile ? 15 : 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accent, accent.withOpacity(0.82)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: t.softShadow,
      ),
      child: Row(
        children: [
          _buildLogoEvento(
            context,
            size: isMobile ? 62 : 72,
            background: onAccent.withOpacity(0.16),
            foreground: onAccent,
            radius: 21,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Você está participando deste evento',
                  style: TextStyle(
                    color: onAccent.withOpacity(0.82),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  evento.nomeEvento,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onAccent,
                    fontSize: isMobile ? 19 : 22,
                    height: 1.08,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  runSpacing: 6,
                  children: [
                    _buildHeaderChip(
                      context,
                      text: evento.statusPagamentoLabel.toUpperCase(),
                      icon: evento.pagamentoQuitado
                          ? Icons.check_circle_rounded
                          : Icons.pending_actions_rounded,
                      color: _pagamentoColor(context),
                      onColorBackground: accent,
                    ),
                    _buildHeaderChip(
                      context,
                      text: evento.origemPagamentoLabel.toUpperCase(),
                      icon: evento.possuiPatrocinio
                          ? Icons.volunteer_activism_rounded
                          : Icons.payments_rounded,
                      color: _origemPagamentoColor(context),
                      onColorBackground: accent,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniResumoEvento(BuildContext context) {
    final t = context.uai;
    final pagamentoColor = _pagamentoColor(context);
    final origemColor = _origemPagamentoColor(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Row(
        children: [
          _buildLogoEvento(
            context,
            size: 48,
            background: t.cardAlt,
            foreground: t.primary,
            radius: 16,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  evento.nomeEvento,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildTinyChip(
                      context,
                      text: evento.statusPagamentoLabel,
                      icon: Icons.verified_rounded,
                      color: pagamentoColor,
                    ),
                    _buildTinyChip(
                      context,
                      text: evento.origemPagamentoLabel,
                      icon: evento.possuiPatrocinio
                          ? Icons.volunteer_activism_rounded
                          : Icons.payments_rounded,
                      color: origemColor,
                    ),
                    if (evento.temCamisa)
                      _buildTinyChip(
                        context,
                        text: evento.tamanhoCamisa,
                        icon: Icons.checkroom_rounded,
                        color: t.warning,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoEvento(
      BuildContext context, {
        required double size,
        required Color background,
        required Color foreground,
        required double radius,
      }) {
    final logo = evento.logoEventoUrl.trim();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: foreground.withOpacity(0.15)),
      ),
      clipBehavior: Clip.antiAlias,
      child: logo.isNotEmpty
          ? Image.network(
        logo,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          return Icon(
            Icons.emoji_events_rounded,
            color: foreground,
            size: size * 0.52,
          );
        },
      )
          : Icon(
        Icons.emoji_events_rounded,
        color: foreground,
        size: size * 0.52,
      ),
    );
  }

  Widget _buildHeaderChip(
      BuildContext context, {
        required String text,
        required IconData icon,
        required Color color,
        required Color onColorBackground,
      }) {
    final visible = _ensureVisible(color, onColorBackground);
    final foreground = _readableOn(visible);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: visible,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: foreground.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: foreground, size: 13),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: foreground,
              fontSize: 10.3,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTinyChip(
      BuildContext context, {
        required String text,
        required IconData icon,
        required Color color,
      }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.09), t.cardAlt),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 12),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: accent,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinanceiroResumo(BuildContext context) {
    final t = context.uai;
    final color = _pagamentoColor(context);
    final accent = _ensureVisible(color, t.card);
    final origemAccent = _ensureVisible(_origemPagamentoColor(context), t.card);
    final pagoAccent = _ensureVisible(t.success, t.card);
    final saldoAccent = _ensureVisible(_saldoColor(context), t.card);
    final totalAccent = _ensureVisible(t.primary, t.card);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withOpacity(0.14)),
        boxShadow: t.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 53,
                height: 53,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(accent.withOpacity(0.10), t.cardAlt),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  evento.pagamentoQuitado
                      ? Icons.check_circle_rounded
                      : Icons.payments_rounded,
                  color: accent,
                  size: 29,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      evento.statusPagamentoLabel,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      evento.origemPagamentoLabel,
                      style: TextStyle(
                        color: origemAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      evento.pagamentoQuitado
                          ? 'Sua participação está quitada neste evento.'
                          : 'Ainda existe valor pendente para este evento.',
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 520;

              if (narrow) {
                return Column(
                  children: [
                    _buildFinanceResumoTile(
                      context,
                      title: 'Total',
                      value: _formatMoney(evento.valorTotal),
                      icon: Icons.receipt_long_rounded,
                      accent: totalAccent,
                    ),
                    const SizedBox(height: 10),
                    _buildFinanceResumoTile(
                      context,
                      title: 'Valor pago',
                      value: _formatMoney(evento.totalPago),
                      icon: Icons.check_circle_rounded,
                      accent: pagoAccent,
                    ),
                    const SizedBox(height: 10),
                    _buildFinanceResumoTile(
                      context,
                      title: 'Saldo devedor',
                      value: _formatMoney(evento.saldo),
                      icon: evento.saldo > 0.01
                          ? Icons.error_rounded
                          : Icons.verified_rounded,
                      accent: saldoAccent,
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: _buildFinanceResumoTile(
                      context,
                      title: 'Total',
                      value: _formatMoney(evento.valorTotal),
                      icon: Icons.receipt_long_rounded,
                      accent: totalAccent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildFinanceResumoTile(
                      context,
                      title: 'Valor pago',
                      value: _formatMoney(evento.totalPago),
                      icon: Icons.check_circle_rounded,
                      accent: pagoAccent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildFinanceResumoTile(
                      context,
                      title: 'Saldo devedor',
                      value: _formatMoney(evento.saldo),
                      icon: evento.saldo > 0.01
                          ? Icons.error_rounded
                          : Icons.verified_rounded,
                      accent: saldoAccent,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFinanceResumoTile(
      BuildContext context, {
        required String title,
        required String value,
        required IconData icon,
        required Color accent,
      }) {
    final t = context.uai;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.08), t.cardAlt),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(0.14)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: accent, size: 21),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(
                    color: accent,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGraduacaoNovaCard(BuildContext context) {
    final t = context.uai;
    final accent = _ensureVisible(t.warning, t.card);

    final temCordaSvg = _cordaNovaGraduacaoSvg != null;
    final titulo = evento.temNovaGraduacao
        ? evento.graduacaoNova
        : 'Nova graduação não definida';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withOpacity(0.14)),
        boxShadow: t.softShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 53,
            height: 53,
            decoration: BoxDecoration(
              color: Color.alphaBlend(accent.withOpacity(0.10), t.cardAlt),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.workspace_premium_rounded,
              color: accent,
              size: 29,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Graduação do evento',
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  titulo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 14.5,
                    height: 1.12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (!temCordaSvg && evento.temNovaGraduacao) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Corda cadastrada sem cores SVG nesta participação.',
                    style: TextStyle(
                      color: t.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (temCordaSvg) ...[
            const SizedBox(width: 10),
            SizedBox(
              width: 86,
              height: 58,
              child: SvgPicture.string(
                _cordaNovaGraduacaoSvg!,
                fit: BoxFit.contain,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSection(
      BuildContext context, {
        required IconData icon,
        required String title,
        required Color color,
        required List<Widget> children,
      }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 39,
                height: 39,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(accent.withOpacity(0.09), t.cardAlt),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accent, size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    final t = context.uai;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value.trim().isEmpty ? 'Não informado' : value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 12.7,
                height: 1.18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinanceiroInfoRow(
      BuildContext context,
      String label,
      String value, {
        required Color accent,
        bool emphasize = false,
      }) {
    final t = context.uai;
    final visible = _ensureVisible(accent, t.card);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          visible.withOpacity(emphasize ? 0.10 : 0.06),
          t.cardAlt,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: visible.withOpacity(0.14)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: TextStyle(
                color: emphasize ? visible : t.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value.trim().isEmpty ? 'Não informado' : value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: visible,
                fontSize: emphasize ? 13.4 : 12.8,
                height: 1.18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCertificadoSection(BuildContext context) {
    final t = context.uai;
    final accent = evento.temCertificado
        ? _ensureVisible(t.success, t.card)
        : _ensureVisible(t.warning, t.card);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withOpacity(0.14)),
        boxShadow: t.softShadow,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 49,
                height: 49,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(accent.withOpacity(0.10), t.cardAlt),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(
                  evento.temCertificado
                      ? Icons.picture_as_pdf_rounded
                      : Icons.hourglass_bottom_rounded,
                  color: accent,
                  size: 27,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Certificado',
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      evento.certificadoLabel,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _abrirCertificado,
              icon: Icon(
                evento.temCertificado
                    ? Icons.visibility_rounded
                    : Icons.lock_clock_rounded,
              ),
              label: Text(
                evento.temCertificado
                    ? 'ABRIR CERTIFICADO NO APP'
                    : 'CERTIFICADO AINDA NÃO LIBERADO',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: _readableOn(accent),
                padding: const EdgeInsets.symmetric(vertical: 13),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                ),
              ),
            ),
          ),
          const SizedBox(height: 9),
          _buildReadonlyNotice(
            context,
            icon: Icons.visibility_outlined,
            color: t.info,
            text:
            'O certificado abre dentro do app apenas para visualização. '
                'A opção de baixar deve ser liberada somente após a finalização do evento.',
          ),
        ],
      ),
    );
  }

  Widget _buildReadonlyNotice(
      BuildContext context, {
        required IconData icon,
        required Color color,
        required String text,
      }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.08), t.card),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: t.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 11.8,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
