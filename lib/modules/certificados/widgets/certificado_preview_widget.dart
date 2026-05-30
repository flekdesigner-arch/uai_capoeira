import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/certificados/models/certificado_preview_data.dart';
import 'package:uai_capoeira/modules/certificados/models/certificado_slot_model.dart';
import 'package:uai_capoeira/modules/certificados/models/certificado_template_tipo.dart';
import 'package:uai_capoeira/modules/certificados/services/certificado_svg_service.dart';

class CertificadoPreviewWidget extends StatefulWidget {
  final CertificadoTemplateTipo tipo;
  final Color cor1;
  final Color cor2;
  final Color corContorno;
  final CertificadoPreviewData? data;
  final bool showHeader;
  final bool showDebugInfo;
  final bool showTextOverlay;
  final GlobalKey? exportKey;
  final double? maxHeight;

  const CertificadoPreviewWidget({
    super.key,
    required this.tipo,
    required this.cor1,
    required this.cor2,
    this.corContorno = const Color(0xFF373435),
    this.data,
    this.showHeader = true,
    this.showDebugInfo = true,
    this.showTextOverlay = true,
    this.exportKey,
    this.maxHeight,
  });

  @override
  State<CertificadoPreviewWidget> createState() =>
      _CertificadoPreviewWidgetState();
}

class _CertificadoPreviewWidgetState extends State<CertificadoPreviewWidget> {
  final CertificadoSvgService _service = const CertificadoSvgService();

  late Future<_CertificadoPreviewPayload> _futurePayload;

  @override
  void initState() {
    super.initState();
    _reloadPayload();
  }

  @override
  void didUpdateWidget(covariant CertificadoPreviewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    final changed = oldWidget.tipo != widget.tipo ||
        oldWidget.cor1 != widget.cor1 ||
        oldWidget.cor2 != widget.cor2 ||
        oldWidget.corContorno != widget.corContorno ||
        oldWidget.data != widget.data ||
        oldWidget.showTextOverlay != widget.showTextOverlay;

    if (changed) {
      _reloadPayload();
    }
  }

  void _reloadPayload() {
    _futurePayload = _loadPayload();
  }

  Future<_CertificadoPreviewPayload> _loadPayload() async {
    final svg = await _service.gerarPreviewColorido(
      tipo: widget.tipo,
      cor1: widget.cor1,
      cor2: widget.cor2,
      corContorno: widget.corContorno,
    );

    final slots = await _service.carregarSlotsDoGuia(widget.tipo);

    return _CertificadoPreviewPayload(svg: svg, slots: slots);
  }

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

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final accent = _ensureVisible(t.primary, t.card);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showHeader) ...[
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                      accent.withOpacity(0.12),
                      t.cardAlt,
                    ),
                    borderRadius: BorderRadius.circular(t.buttonRadius),
                    border: Border.all(color: accent.withOpacity(0.14)),
                  ),
                  child: Icon(widget.tipo.icon, color: accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.tipo.nome,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.showTextOverlay
                            ? 'Prévia com textos posicionados pelo SVG guia'
                            : 'Prévia SVG com corda dinâmica',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.textSecondary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                _ColorDot(color: widget.cor1),
                const SizedBox(width: 5),
                _ColorDot(color: widget.cor2),
              ],
            ),
            const SizedBox(height: 12),
          ],
          FutureBuilder<_CertificadoPreviewPayload>(
            future: _futurePayload,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _buildPreviewFrame(
                  childBuilder: (_, __, ___) => Center(
                    child: CircularProgressIndicator(color: t.primary),
                  ),
                );
              }

              if (snapshot.hasError ||
                  (snapshot.data?.svg.trim().isEmpty ?? true)) {
                return _buildPreviewFrame(
                  childBuilder: (_, __, ___) => Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: t.error,
                          size: 44,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Não foi possível carregar este template.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: t.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (snapshot.error != null) ...[
                          const SizedBox(height: 5),
                          Text(
                            snapshot.error.toString(),
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: t.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }

              final payload = snapshot.data!;

              final data = widget.data ??
                  CertificadoPreviewData.exemplo(widget.tipo);

              final previewFrame = _buildPreviewFrame(
                exportKey: widget.exportKey,
                childBuilder: (innerWidth, innerHeight, scale) {
                  return _buildCertificateStack(
                    svg: payload.svg,
                    slots: payload.slots,
                    data: data,
                    scale: scale,
                    loadingColor: t.primary,
                  );
                },
              );

              return InkWell(
                onTap: () => _abrirPreviewTelaCheia(
                  payload: payload,
                  data: data,
                ),
                borderRadius: BorderRadius.circular(t.cardRadius - 4),
                child: previewFrame,
              );
            },
          ),
          if (widget.showDebugInfo) ...[
            const SizedBox(height: 10),
            FutureBuilder<_CertificadoPreviewPayload>(
              future: _futurePayload,
              builder: (context, snapshot) {
                final slotsCount = snapshot.data?.slots.length ?? 0;

                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoChip(
                      icon: Icons.tag_rounded,
                      label: widget.tipo.codigo,
                      color: accent,
                    ),
                    _InfoChip(
                      icon: Icons.brush_rounded,
                      label: 'cor1/cor2 ativos',
                      color: _ensureVisible(widget.cor1, t.card),
                    ),
                    _InfoChip(
                      icon: Icons.view_quilt_rounded,
                      label: '$slotsCount slots lidos',
                      color: t.info,
                    ),
                    _InfoChip(
                      icon: Icons.check_circle_rounded,
                      label: 'SVG pronto',
                      color: t.success,
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  void _abrirPreviewTelaCheia({
    required _CertificadoPreviewPayload payload,
    required CertificadoPreviewData data,
  }) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.92),
      builder: (dialogContext) {
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: SafeArea(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.92),
                    border: const Border(
                      bottom: BorderSide(color: Colors.white12),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        widget.tipo.icon,
                        color: Colors.white,
                        size: 22,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.tipo.nome,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              'Prévia em tamanho real • arraste e use zoom',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.72),
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fechar',
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 5,
                    boundaryMargin: const EdgeInsets.all(120),
                    child: Center(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final availableWidth = constraints.maxWidth;
                          final availableHeight = constraints.maxHeight;

                          // A4 paisagem: 297 x 210.
                          // Aqui usamos o maior tamanho possível sem cortar.
                          final scaleByWidth = availableWidth / 297;
                          final scaleByHeight = availableHeight / 210;
                          final baseScale =
                          scaleByWidth < scaleByHeight ? scaleByWidth : scaleByHeight;

                          // Em telas grandes, deixa bem próximo do tamanho cheio.
                          final scale = baseScale.clamp(1.0, 4.0);

                          return Container(
                            width: 297 * scale,
                            height: 210 * scale,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.45),
                                  blurRadius: 24,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: _buildCertificateStack(
                              svg: payload.svg,
                              slots: payload.slots,
                              data: data,
                              scale: scale,
                              loadingColor: const Color(0xFFB71C1C),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                  color: Colors.black.withOpacity(0.92),
                  child: Text(
                    'Toque no X para fechar. Use scroll/gesto de pinça para aproximar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.70),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCertificateStack({
    required String svg,
    required Map<String, CertificadoSlotModel> slots,
    required CertificadoPreviewData data,
    required double scale,
    Color loadingColor = const Color(0xFFB71C1C),
  }) {
    // Não usa context.uai aqui.
    // Essa função também é chamada dentro do Dialog fullscreen e, em mudança brusca
    // de tamanho da janela, consultar InheritedWidget pelo context antigo pode gerar:
    // "Looking up a deactivated widget's ancestor is unsafe."
    return Stack(
      fit: StackFit.expand,
      children: [
        SvgPicture.string(
          svg,
          fit: BoxFit.contain,
          placeholderBuilder: (_) {
            return Center(
              child: CircularProgressIndicator(color: loadingColor),
            );
          },
        ),
        if (widget.showTextOverlay)
          ..._buildTextOverlay(
            data: data,
            slots: slots,
            innerWidth: 297 * scale,
            innerHeight: 210 * scale,
            scale: scale,
          ),
      ],
    );
  }

  List<Widget> _buildTextOverlay({
    required CertificadoPreviewData data,
    required Map<String, CertificadoSlotModel> slots,
    required double innerWidth,
    required double innerHeight,
    required double scale,
  }) {
    final widgets = <Widget>[];

    const vinhoTexto = Color(0xFF1A0202);
    const linhaPontilhada = Color(0xFF8E2025);

    Alignment bottomAlignmentFromTextAlign(TextAlign align) {
      switch (align) {
        case TextAlign.left:
        case TextAlign.start:
          return Alignment.bottomLeft;
        case TextAlign.right:
        case TextAlign.end:
          return Alignment.bottomRight;
        case TextAlign.center:
        case TextAlign.justify:
          return Alignment.bottomCenter;
      }
    }

    Alignment centerAlignmentFromTextAlign(TextAlign align) {
      switch (align) {
        case TextAlign.left:
        case TextAlign.start:
          return Alignment.centerLeft;
        case TextAlign.right:
        case TextAlign.end:
          return Alignment.centerRight;
        case TextAlign.center:
        case TextAlign.justify:
          return Alignment.center;
      }
    }

    void addSingleLine({
      required String slotId,
      required String value,
      required double fontSizeMm,
      FontWeight fontWeight = FontWeight.w800,
      Color color = vinhoTexto,
      TextAlign align = TextAlign.center,
      String? fontFamily,
      double letterSpacingMm = 0.0,
      bool uppercase = false,
      double height = 1.0,
      double bottomOffsetMm = 0.0,
      double leftOffsetMm = 0.0,
      double topOffsetMm = 0.0,
      double widthExtraMm = 0.0,
    }) {
      final slot = slots[slotId];
      final clean = value.trim();

      if (slot == null || clean.isEmpty) return;

      widgets.add(
        _PositionedSlotText(
          slot: slot,
          scale: scale,
          topOffset: topOffsetMm * scale,
          leftOffset: leftOffsetMm * scale,
          widthExtra: widthExtraMm * scale,
          heightExtra: bottomOffsetMm * scale,
          child: Align(
            alignment: bottomAlignmentFromTextAlign(align),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: bottomAlignmentFromTextAlign(align),
              child: Text(
                uppercase ? clean.toUpperCase() : clean,
                maxLines: 1,
                textAlign: align,
                style: TextStyle(
                  color: color,
                  fontSize: fontSizeMm * scale,
                  fontWeight: fontWeight,
                  letterSpacing: letterSpacingMm * scale,
                  fontFamily: fontFamily,
                  height: height,
                ),
              ),
            ),
          ),
        ),
      );
    }

    void addMultiLine({
      required String slotId,
      required String value,
      required double fontSizeMm,
      FontWeight fontWeight = FontWeight.w700,
      Color color = vinhoTexto,
      TextAlign align = TextAlign.center,
      String? fontFamily,
      double height = 1.25,
      int? maxLines,
      bool uppercase = false,
      bool alignTop = false,
      double topOffsetMm = 0.0,
      double leftOffsetMm = 0.0,
      double widthExtraMm = 0.0,
      double heightExtraMm = 0.0,
    }) {
      final slot = slots[slotId];
      final clean = value.trim();

      if (slot == null || clean.isEmpty) return;

      widgets.add(
        _PositionedSlotText(
          slot: slot,
          scale: scale,
          topOffset: topOffsetMm * scale,
          leftOffset: leftOffsetMm * scale,
          widthExtra: widthExtraMm * scale,
          heightExtra: heightExtraMm * scale,
          child: Align(
            alignment: alignTop
                ? Alignment.topCenter
                : centerAlignmentFromTextAlign(align),
            child: Text(
              uppercase ? clean.toUpperCase() : clean,
              textAlign: align,
              maxLines: maxLines,
              softWrap: true,
              overflow: TextOverflow.visible,
              style: TextStyle(
                color: color,
                fontSize: fontSizeMm * scale,
                fontWeight: fontWeight,
                fontFamily: fontFamily,
                height: height,
              ),
            ),
          ),
        ),
      );
    }

    // As linhas pontilhadas ficam 100% por conta do SVG original.
    // O overlay daqui desenha apenas os textos.

    // Nome do aluno: maior, Arial Bold, base inferior do retângulo guia.
    addSingleLine(
      slotId: CertificadoSlotIds.alunoNome,
      value: data.alunoNome,
      fontSizeMm: 6.65,
      fontWeight: FontWeight.w900,
      color: vinhoTexto,
      fontFamily: 'Arial',
      letterSpacingMm: 0.015,
      uppercase: true,
      bottomOffsetMm: 0.08,
    );

    // CPF: Square721BT.
    // Alguns guias podem não ter o retângulo com id="cpf".
    // Quando isso acontecer, criamos um slot fallback entre o nome e a graduação.
    if (widget.tipo.exigeCpf && data.cpfFormatado.isNotEmpty) {
      final cpfSlotOriginal = slots[CertificadoSlotIds.cpf];
      final nomeSlot = slots[CertificadoSlotIds.alunoNome];
      final graduacaoSlot = slots[CertificadoSlotIds.graduacaoNova];

      final cpfSlot = cpfSlotOriginal ??
          (nomeSlot != null && graduacaoSlot != null
              ? CertificadoSlotModel(
            id: CertificadoSlotIds.cpf,
            x: nomeSlot.x + (nomeSlot.width * 0.34),
            y: nomeSlot.bottom + 0.25,
            width: nomeSlot.width * 0.32,
            height: (graduacaoSlot.y - nomeSlot.bottom).clamp(3.0, 6.0),
          )
              : null);

      if (cpfSlot != null) {
        widgets.add(
          _PositionedSlotText(
            slot: cpfSlot,
            scale: scale,
            heightExtra: 0.08 * scale,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.bottomCenter,
                child: Text(
                  data.cpfFormatado,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: vinhoTexto,
                    fontSize: 3.55 * scale,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Square721BT',
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }

    // Graduação: 3mm para a direita, Arial Bold, cor do nome.
    addSingleLine(
      slotId: CertificadoSlotIds.graduacaoNova,
      value: data.graduacaoNova,
      fontSizeMm: 5.25,
      fontWeight: FontWeight.w900,
      color: vinhoTexto,
      align: TextAlign.left,
      fontFamily: 'Arial',
      uppercase: true,
      leftOffsetMm: 3.0,
      widthExtraMm: -3.0,
      bottomOffsetMm: 0.10,
    );

    // Frase: agora alinha no topo do retângulo, não no centro.
    // Ela precisa ocupar visualmente a faixa como no modelo do Photoshop.
    addMultiLine(
      slotId: CertificadoSlotIds.frase,
      value: data.fraseFinal(
        tipo: widget.tipo,
        tituloGraduacao: _tituloParaTipo(widget.tipo),
        corda: data.graduacaoNova,
      ),
      fontSizeMm: 5.05,
      fontWeight: FontWeight.w500,
      color: vinhoTexto,
      align: TextAlign.center,
      fontFamily: 'EngraversGothicBT',
      height: 1.22,
      uppercase: true,
      alignTop: true,
      topOffsetMm: 0.55,
      leftOffsetMm: -2.0,
      widthExtraMm: 4.0,
    );

    for (var i = 0; i < 5; i++) {
      final assinatura = i < data.assinaturas.length ? data.assinaturas[i] : null;
      if (assinatura == null) continue;

      final numero = i + 1;

      addSingleLine(
        slotId: 'assinatura$numero',
        value: assinatura.nome,
        fontSizeMm: 5.05,
        fontWeight: FontWeight.w500,
        color: vinhoTexto,
        fontFamily: 'Arial',
        uppercase: true,
        bottomOffsetMm: 0.05,
      );

      addSingleLine(
        slotId: 'apelido$numero',
        value: assinatura.apelido,
        fontSizeMm: 3.85,
        fontWeight: FontWeight.w500,
        color: vinhoTexto,
        fontFamily: 'SitkaText',
        uppercase: true,
        bottomOffsetMm: 0.05,
      );
    }

    addSingleLine(
      slotId: CertificadoSlotIds.localData,
      value: data.localData,
      fontSizeMm: 3.55,
      fontWeight: FontWeight.w700,
      color: vinhoTexto,
      fontFamily: 'Square721BT',
      letterSpacingMm: 0.01,
      uppercase: true,
      bottomOffsetMm: 0.08,
    );

    return widgets;
  }

  String _tituloParaTipo(CertificadoTemplateTipo tipo) {
    switch (tipo) {
      case CertificadoTemplateTipo.certificadoSemCpf:
        return 'ALUNO';
      case CertificadoTemplateTipo.certificadoComCpf:
        return 'INSTRUTOR';
      case CertificadoTemplateTipo.diploma:
        return 'PROFESSOR';
    }
  }

  Alignment _alignmentFromTextAlign(TextAlign align) {
    switch (align) {
      case TextAlign.left:
      case TextAlign.start:
        return Alignment.centerLeft;
      case TextAlign.right:
      case TextAlign.end:
        return Alignment.centerRight;
      case TextAlign.center:
      case TextAlign.justify:
        return Alignment.center;
    }
  }

  Widget _buildPreviewFrame({
    required Widget Function(double innerWidth, double innerHeight, double scale)
    childBuilder,
    GlobalKey? exportKey,
  }) {
    final t = context.uai;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = widget.maxHeight ?? 520.0;
        final calculatedHeight = (constraints.maxWidth / (297 / 210))
            .clamp(180.0, maxHeight);

        // Esse padding é apenas visual no painel.
        // A exportação NÃO captura esse padding, nem a borda arredondada do card.
        const padding = 8.0;
        final innerWidth = constraints.maxWidth - (padding * 2);
        final innerHeight = calculatedHeight - (padding * 2);
        final scaleX = innerWidth / 297.0;
        final scaleY = innerHeight / 210.0;
        final scale = scaleX < scaleY ? scaleX : scaleY;

        final certificadoLimpo = SizedBox(
          width: 297 * scale,
          height: 210 * scale,
          child: childBuilder(297 * scale, 210 * scale, scale),
        );

        final conteudo = exportKey == null
            ? certificadoLimpo
            : RepaintBoundary(
          key: exportKey,
          child: certificadoLimpo,
        );

        return Container(
          height: calculatedHeight,
          padding: const EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(t.cardRadius - 4),
            border: Border.all(color: t.border),
          ),
          child: Center(child: conteudo),
        );
      },
    );
  }
}

class _PositionedSlotText extends StatelessWidget {
  final CertificadoSlotModel slot;
  final double scale;
  final Widget child;
  final double topOffset;
  final double leftOffset;
  final double widthExtra;
  final double heightExtra;

  const _PositionedSlotText({
    required this.slot,
    required this.scale,
    required this.child,
    this.topOffset = 0,
    this.leftOffset = 0,
    this.widthExtra = 0,
    this.heightExtra = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: (slot.x * scale) + leftOffset,
      top: (slot.y * scale) + topOffset,
      width: (slot.width * scale) + widthExtra,
      height: (slot.height * scale) + heightExtra,
      child: IgnorePointer(child: child),
    );
  }
}

class _CertificadoPreviewPayload {
  final String svg;
  final Map<String, CertificadoSlotModel> slots;

  const _CertificadoPreviewPayload({
    required this.svg,
    required this.slots,
  });
}

class _ColorDot extends StatelessWidget {
  final Color color;

  const _ColorDot({required this.color});

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: t.border, width: 1.5),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  Color _ensureVisible(BuildContext context, Color color) {
    final background = context.uai.card;
    final diff = (color.computeLuminance() - background.computeLuminance()).abs();
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
    final accent = _ensureVisible(context, color);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.10), t.cardAlt),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
