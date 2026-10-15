import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/certificados/models/certificado_preview_data.dart';
import 'package:uai_capoeira/modules/certificados/models/certificado_slot_model.dart';
import 'package:uai_capoeira/modules/certificados/models/certificado_studio_model.dart';
import 'package:uai_capoeira/modules/certificados/models/certificado_template_tipo.dart';
import 'package:uai_capoeira/modules/certificados/services/certificado_svg_service.dart';
import 'package:uai_capoeira/modules/eventos/models/evento_model.dart';

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

  /// Configuração visual dinâmica dos textos.
  /// Quando não vier nada, usa o padrão atual do certificado.
  final Map<String, CertificadoTextoCampoConfig>? textosConfig;
  final CertificadoVisualConfig? visualConfig;
  final CertificadoStudioConfig? studioConfig;
  final bool studioInteractive;
  final String? selectedStudioLayerId;
  final ValueChanged<String>? onStudioLayerSelected;
  final ValueChanged<CertificadoStudioLayer>? onStudioLayerChanged;
  final String? selectedStudioTextId;
  final ValueChanged<String>? onStudioTextSelected;
  final ValueChanged<CertificadoStudioTextLayer>? onStudioTextChanged;
  final bool studioQrSelected;
  final VoidCallback? onStudioQrSelected;
  final ValueChanged<CertificadoStudioQrConfig>? onStudioQrChanged;

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
    this.textosConfig,
    this.visualConfig,
    this.studioConfig,
    this.studioInteractive = false,
    this.selectedStudioLayerId,
    this.onStudioLayerSelected,
    this.onStudioLayerChanged,
    this.selectedStudioTextId,
    this.onStudioTextSelected,
    this.onStudioTextChanged,
    this.studioQrSelected = false,
    this.onStudioQrSelected,
    this.onStudioQrChanged,
  });

  @override
  State<CertificadoPreviewWidget> createState() =>
      _CertificadoPreviewWidgetState();
}

class _CertificadoPreviewWidgetState extends State<CertificadoPreviewWidget> {
  final CertificadoSvgService _service = const CertificadoSvgService();

  bool get _touchStudioUi =>
      widget.studioInteractive && MediaQuery.sizeOf(context).shortestSide < 700;

  double get _studioHandleSize => _touchStudioUi ? 24.0 : 12.0;
  double get _studioHandleOffset => _touchStudioUi ? -10.0 : -5.0;

  late Future<_CertificadoPreviewPayload> _futurePayload;

  @override
  void initState() {
    super.initState();
    _reloadPayload();
  }

  @override
  void didUpdateWidget(covariant CertificadoPreviewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    final changed =
        oldWidget.tipo != widget.tipo ||
        oldWidget.cor1 != widget.cor1 ||
        oldWidget.cor2 != widget.cor2 ||
        oldWidget.corContorno != widget.corContorno ||
        _previewDataFingerprint(oldWidget.data) !=
            _previewDataFingerprint(widget.data) ||
        oldWidget.textosConfig != widget.textosConfig ||
        oldWidget.visualConfig != widget.visualConfig ||
        _studioAssetsFingerprint(oldWidget.studioConfig) !=
            _studioAssetsFingerprint(widget.studioConfig) ||
        oldWidget.showTextOverlay != widget.showTextOverlay;

    if (changed) {
      _reloadPayload();
    }
  }

  String _previewDataFingerprint(CertificadoPreviewData? data) {
    if (data == null) return '';
    final buffer = StringBuffer()
      ..write(data.alunoNome)
      ..write('|${data.cpf}')
      ..write('|${data.sexo}')
      ..write('|${data.graduacaoNova}')
      ..write('|${data.frase}')
      ..write('|${data.localData}');
    for (final a in data.assinaturas) {
      buffer.write('|${a.nome}:${a.apelido}');
    }
    return buffer.toString();
  }

  String _studioAssetsFingerprint(CertificadoStudioConfig? studio) {
    if (studio == null) return '';
    final buffer = StringBuffer()
      ..write(studio.baseEmBranco)
      ..write('|')
      ..write(studio.baseSvgStoragePath)
      ..write('|${studio.basePreviewStoragePath}')
      ..write('|${studio.orientacaoPagina}:${studio.paginaLarguraMm}:${studio.paginaAlturaMm}:${studio.ajusteBaseSvg}')
      ..write('|')
      ..write(studio.substituicoesCor.entries.map((e) => '${e.key}:${e.value}').join(','))
      ..write('|qr:${studio.qrCode.toMap()}');
    for (final layer in studio.camadas) {
      buffer
        ..write('|${layer.id}:${layer.storagePath}:${layer.previewStoragePath}:${layer.visivel}:')
        ..write(layer.substituicoesCor.entries.map((e) => '${e.key}:${e.value}').join(','));
    }
    return buffer.toString();
  }

  Color _hexColor(String? value, Color fallback) {
    final clean = (value ?? '').trim().replaceAll('#', '');
    if (!RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(clean)) return fallback;
    return Color(int.parse('FF$clean', radix: 16));
  }

  void _reloadPayload() {
    _futurePayload = _loadPayload();
  }

  Future<_CertificadoPreviewPayload> _loadPayload() async {
    final visual = widget.visualConfig;
    final studio = widget.studioConfig;
    final externalBase = studio?.baseSvgStoragePath?.trim().isNotEmpty == true;
    final previewPath = studio?.basePreviewStoragePath?.trim() ?? '';

    Uint8List? basePreviewBytes;
    String svg;

    if (externalBase && previewPath.isNotEmpty) {
      // SVG Corel pesado: o Canvas usa o PNG cacheado e não tenta compilar
      // milhares de paths no flutter_svg. O SVG mestre continua no Storage.
      basePreviewBytes = await _service.carregarBytesStorage(
        previewPath,
        maxBytes: 20 * 1024 * 1024,
      );
      svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $_documentWidth $_documentHeight"></svg>';
    } else {
      svg = await _service.gerarPreviewColorido(
        tipo: widget.tipo,
        cor1: widget.cor1,
        cor2: widget.cor2,
        corContorno: widget.corContorno,
        corFundo: visual == null
            ? null
            : _hexColor(visual.corFundo, const Color(0xFFEBECEC)),
        corEstrutura: visual == null
            ? null
            : _hexColor(visual.corEstrutura, const Color(0xFF373435)),
        corDestaque: visual == null
            ? null
            : _hexColor(visual.corDestaque, const Color(0xFFB83336)),
        corDetalhe: visual == null
            ? null
            : _hexColor(visual.corDetalhe, const Color(0xFFBDBFC1)),
        studioConfig: widget.studioConfig,
      );
    }

    final baseSlots = await _service.carregarSlotsDoGuia(widget.tipo);
    final slots = _service.aplicarLayoutsStudio(baseSlots, widget.studioConfig);
    final camadas = <_CertificadoStudioLayerPayload>[];
    final studioLayers = studio?.camadas
            .where((e) => e.visivel && e.storagePath.trim().isNotEmpty)
            .toList() ??
        const <CertificadoStudioLayer>[];
    for (final layer in studioLayers) {
      final layerPreviewPath = layer.previewStoragePath?.trim() ?? '';
      if (layerPreviewPath.isNotEmpty) {
        final bytes = await _service.carregarBytesStorage(
          layerPreviewPath,
          maxBytes: 20 * 1024 * 1024,
        );
        camadas.add(_CertificadoStudioLayerPayload(layer: layer, previewBytes: bytes));
      } else {
        var layerSvg = await _service.carregarSvgStorage(layer.storagePath);
        layerSvg = _service.aplicarSubstituicoesCores(layerSvg, layer.substituicoesCor);
        camadas.add(_CertificadoStudioLayerPayload(layer: layer, svg: layerSvg));
      }
    }

    return _CertificadoPreviewPayload(
      svg: svg,
      basePreviewBytes: basePreviewBytes,
      slots: slots,
      camadas: camadas,
    );
  }

  double get _documentWidth => widget.studioConfig?.larguraDocumentoMm ?? 297.0;
  double get _documentHeight => widget.studioConfig?.alturaDocumentoMm ?? 210.0;



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
      child: LayoutBuilder(
        builder: (context, outerConstraints) {
          final shortViewport =
              outerConstraints.hasBoundedHeight && outerConstraints.maxHeight < 560;

          final content = Column(
            mainAxisSize: MainAxisSize.min,
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
                      accent.withAlpha(31),
                      t.cardAlt,
                    ),
                    borderRadius: BorderRadius.circular(t.buttonRadius),
                    border: Border.all(color: accent.withAlpha(36)),
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
                            ? 'Prévia com textos dinâmicos pelo SVG guia'
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
                  childBuilder: (_, _, _) => Center(
                    child: CircularProgressIndicator(color: t.primary),
                  ),
                );
              }

              if (snapshot.hasError ||
                  (snapshot.data?.svg.trim().isEmpty ?? true)) {
                return _buildPreviewFrame(
                  childBuilder: (_, _, _) => Padding(
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

              final data =
                  widget.data ?? CertificadoPreviewData.exemplo(widget.tipo);

              final previewFrame = _buildPreviewFrame(
                exportKey: widget.exportKey,
                childBuilder: (innerWidth, innerHeight, scale) {
                  return _buildCertificateStack(
                    svg: payload.svg,
                    basePreviewBytes: payload.basePreviewBytes,
                    slots: payload.slots,
                    camadas: payload.camadas,
                    data: data,
                    scale: scale,
                    loadingColor: t.primary,
                  );
                },
              );

              return InkWell(
                onTap: () =>
                    _abrirPreviewTelaCheia(payload: payload, data: data),
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
          );

          // Em janelas menores, split view, PWA e celulares a altura disponível
          // pode ser menor que a altura natural do preview + cabeçalho/chips.
          // Em vez de estourar RenderFlex, permitimos rolagem vertical local.
          // Em telas grandes o widget continua sem scroll e com o layout atual.
          if (shortViewport) {
            return Scrollbar(
              thumbVisibility: false,
              child: SingleChildScrollView(
                primary: false,
                physics: const ClampingScrollPhysics(),
                child: content,
              ),
            );
          }

          return content;
        },
      ),
    );
  }

  void _abrirPreviewTelaCheia({
    required _CertificadoPreviewPayload payload,
    required CertificadoPreviewData data,
  }) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withAlpha(235),
      builder: (dialogContext) {
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: SafeArea(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(235),
                    border: const Border(
                      bottom: BorderSide(color: Colors.white12),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(widget.tipo.icon, color: Colors.white, size: 22),
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
                                color: Colors.white.withAlpha(184),
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

                          // Documento A4 definido pelo Studio.
                          final pageW = _documentWidth;
                          final pageH = _documentHeight;
                          final scaleByWidth = availableWidth / pageW;
                          final scaleByHeight = availableHeight / pageH;
                          final baseScale = scaleByWidth < scaleByHeight
                              ? scaleByWidth
                              : scaleByHeight;

                          // Em telas grandes, deixa bem próximo do tamanho cheio.
                          final scale = baseScale.clamp(1.0, 4.0);

                          return Container(
                            width: pageW * scale,
                            height: pageH * scale,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withAlpha(115),
                                  blurRadius: 24,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: _buildCertificateStack(
                              svg: payload.svg,
                              basePreviewBytes: payload.basePreviewBytes,
                              slots: payload.slots,
                              camadas: payload.camadas,
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
                  color: Colors.black.withAlpha(235),
                  child: Text(
                    'Toque no X para fechar. Use scroll/gesto de pinça para aproximar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withAlpha(179),
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
    Uint8List? basePreviewBytes,
    required Map<String, CertificadoSlotModel> slots,
    required List<_CertificadoStudioLayerPayload> camadas,
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
        if (basePreviewBytes != null)
          Image.memory(
            basePreviewBytes,
            fit: BoxFit.fill,
            gaplessPlayback: true,
            filterQuality: FilterQuality.high,
          )
        else
          SvgPicture.string(
            svg,
            fit: BoxFit.contain,
            placeholderBuilder: (_) {
              return Center(
                child: CircularProgressIndicator(color: loadingColor),
              );
            },
          ),
        ..._buildStudioSvgLayers(camadas, scale),
        if (widget.showTextOverlay)
          ..._buildTextOverlay(
            data: data,
            slots: slots,
            innerWidth: _documentWidth * scale,
            innerHeight: _documentHeight * scale,
            scale: scale,
          ),
        ..._buildStudioTextosLivres(data, scale),
        ..._buildStudioQr(scale),
      ],
    );
  }

  List<Widget> _buildStudioSvgLayers(
    List<_CertificadoStudioLayerPayload> camadas,
    double scale,
  ) {
    return camadas.map((item) {
      var layer = item.layer;
      final currentLayers = widget.studioConfig?.camadas ?? const <CertificadoStudioLayer>[];
      for (final candidate in currentLayers) {
        if (candidate.id == item.layer.id) {
          layer = candidate;
          break;
        }
      }
      final selected = widget.selectedStudioLayerId == layer.id;

      Widget svg = Opacity(
        opacity: layer.opacidade.clamp(0.0, 1.0).toDouble(),
        child: item.previewBytes != null
            ? Image.memory(
                item.previewBytes!,
                fit: BoxFit.fill,
                gaplessPlayback: true,
                filterQuality: FilterQuality.high,
              )
            : SvgPicture.string(item.svg ?? '', fit: BoxFit.fill),
      );

      if (widget.studioInteractive) {
        svg = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onStudioLayerSelected?.call(layer.id),
          onPanStart: (_) => widget.onStudioLayerSelected?.call(layer.id),
          onPanUpdate: layer.bloqueada
              ? null
              : (details) {
                  widget.onStudioLayerChanged?.call(
                    layer.copyWith(
                      x: (layer.x + (details.delta.dx / scale)).clamp(-_documentWidth, _documentWidth * 2).toDouble(),
                      y: (layer.y + (details.delta.dy / scale)).clamp(-_documentHeight, _documentHeight * 2).toDouble(),
                    ),
                  );
                },
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              svg,
              if (selected)
                IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF00BCD4), width: 1.5),
                    ),
                  ),
                ),
              if (selected && !layer.bloqueada)
                Positioned(
                  right: _studioHandleOffset,
                  bottom: _studioHandleOffset,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (details) {
                      widget.onStudioLayerChanged?.call(
                        layer.copyWith(
                          largura: (layer.largura + (details.delta.dx / scale)).clamp(2.0, 594.0).toDouble(),
                          altura: (layer.altura + (details.delta.dy / scale)).clamp(2.0, 420.0).toDouble(),
                        ),
                      );
                    },
                    child: Container(
                      width: _studioHandleSize,
                      height: _studioHandleSize,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00BCD4),
                        border: Border.all(color: Colors.white, width: 1),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      } else {
        svg = IgnorePointer(child: svg);
      }

      return Positioned(
        left: layer.x * scale,
        top: layer.y * scale,
        width: layer.largura * scale,
        height: layer.altura * scale,
        child: svg,
      );
    }).toList();
  }

  List<Widget> _buildStudioQr(double scale) {
    final studio = widget.studioConfig;
    if (studio == null || !studio.qrCode.ativo) return const <Widget>[];
    final qr = studio.qrCode;
    final fg = _colorFromHex(qr.corQrHex, const Color(0xFF111111));
    final bg = _colorFromHex(qr.corFundoHex, Colors.white);
    final border = _colorFromHex(qr.corBordaHex, fg);
    final labelColor = _colorFromHex(qr.corLegendaHex, fg);
    final labelHeightMm = qr.mostrarLegenda ? 5.8 : 0.0;

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: qr.tamanhoMm * scale,
          height: qr.tamanhoMm * scale,
          child: Container(
            padding: EdgeInsets.all(qr.margemMm * scale),
            decoration: BoxDecoration(
              color: qr.fundoTransparente ? Colors.transparent : bg,
              borderRadius: BorderRadius.circular(qr.raioMm * scale),
              border: qr.bordaMm > 0
                  ? Border.all(color: border, width: qr.bordaMm * scale)
                  : null,
            ),
            child: CustomPaint(
              painter: _StudioQrPreviewPainter(foreground: fg),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        if (qr.mostrarLegenda)
          SizedBox(
            height: labelHeightMm * scale,
            child: Center(
              child: Text(
                qr.legenda,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: labelColor,
                  fontSize: (qr.legendaPt / 3.0) * scale,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                ),
              ),
            ),
          ),
      ],
    );

    if (widget.studioInteractive) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onStudioQrSelected,
        onPanStart: (_) => widget.onStudioQrSelected?.call(),
        onPanUpdate: qr.bloqueado
            ? null
            : (details) {
                widget.onStudioQrChanged?.call(
                  qr.copyWith(
                    x: (qr.x + details.delta.dx / scale).clamp(0.0, _documentWidth - 8).toDouble(),
                    y: (qr.y + details.delta.dy / scale).clamp(0.0, _documentHeight - 8).toDouble(),
                  ),
                );
              },
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            content,
            if (widget.studioQrSelected)
              IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF00E5FF), width: 1.5),
                  ),
                ),
              ),
            if (widget.studioQrSelected && !qr.bloqueado)
              Positioned(
                right: _studioHandleOffset,
                bottom: _studioHandleOffset,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) {
                    final delta = (details.delta.dx.abs() >= details.delta.dy.abs()
                            ? details.delta.dx
                            : details.delta.dy) /
                        scale;
                    widget.onStudioQrChanged?.call(
                      qr.copyWith(tamanhoMm: (qr.tamanhoMm + delta).clamp(14.0, 60.0).toDouble()),
                    );
                  },
                  child: Container(
                    width: _studioHandleSize,
                    height: _studioHandleSize,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E5FF),
                      border: Border.all(color: Colors.white, width: 1),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    } else {
      content = IgnorePointer(child: content);
    }

    return [
      Positioned(
        left: qr.x * scale,
        top: qr.y * scale,
        width: qr.tamanhoMm * scale,
        height: (qr.tamanhoMm + labelHeightMm) * scale,
        child: content,
      ),
    ];
  }

  List<Widget> _buildStudioTextosLivres(
    CertificadoPreviewData data,
    double scale,
  ) {
    final textos = widget.studioConfig?.textosLivres ?? const <CertificadoStudioTextLayer>[];
    return textos.where((e) => e.visivel).map((item) {
      final selected = widget.selectedStudioTextId == item.id;
      final text = _resolverTextoStudio(item.textoTemplate, data);
      final align = _textAlignFromConfig(item.alinhamento);
      final color = _colorFromHex(item.corHex, const Color(0xFF1A0202));

      Widget content = Container(
        alignment: align == TextAlign.left
            ? Alignment.topLeft
            : align == TextAlign.right
                ? Alignment.topRight
                : Alignment.topCenter,
        child: _PreviewParagraphText(
          text: text,
          textAlign: align,
          lineHeight: 1.08,
          style: TextStyle(
            color: color,
            fontSize: (item.tamanho / 3.0) * scale,
            fontWeight: item.negrito ? FontWeight.w900 : FontWeight.w500,
            fontFamily: item.fonte,
            height: 1.0,
          ),
        ),
      );

      if (widget.studioInteractive) {
        content = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onStudioTextSelected?.call(item.id),
          onPanStart: (_) => widget.onStudioTextSelected?.call(item.id),
          onPanUpdate: item.bloqueada
              ? null
              : (details) {
                  widget.onStudioTextChanged?.call(
                    item.copyWith(
                      x: (item.x + details.delta.dx / scale).clamp(-_documentWidth, _documentWidth * 2).toDouble(),
                      y: (item.y + details.delta.dy / scale).clamp(-_documentHeight, _documentHeight * 2).toDouble(),
                    ),
                  );
                },
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              content,
              if (selected)
                IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFFFB300), width: 1.4),
                    ),
                  ),
                ),
              if (selected && !item.bloqueada)
                Positioned(
                  right: _studioHandleOffset,
                  bottom: _studioHandleOffset,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (details) {
                      widget.onStudioTextChanged?.call(
                        item.copyWith(
                          largura: (item.largura + details.delta.dx / scale).clamp(4.0, 594.0).toDouble(),
                          altura: (item.altura + details.delta.dy / scale).clamp(3.0, 420.0).toDouble(),
                        ),
                      );
                    },
                    child: Container(
                      width: _studioHandleSize,
                      height: _studioHandleSize,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFB300),
                        border: Border.all(color: Colors.white, width: 1),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      } else {
        content = IgnorePointer(child: content);
      }

      return Positioned(
        left: item.x * scale,
        top: item.y * scale,
        width: item.largura * scale,
        height: item.altura * scale,
        child: content,
      );
    }).toList();
  }

  String _resolverTextoStudio(String template, CertificadoPreviewData data) {
    var out = template;
    final values = <String, String>{
      '{nome}': data.alunoNome,
      '{cpf}': data.cpfFormatado,
      '{graduacao}': data.graduacaoNova,
      '{frase}': data.frase,
      '{local_data}': data.localData,
      '{evento}': 'PRÉVIA DO EVENTO',
    };
    values.forEach((key, value) => out = out.replaceAll(key, value));
    return out;
  }

  CertificadoTextoCampoConfig _textoConfig(String campo) {
    return widget.textosConfig?[campo] ??
        CertificadoTextoCampoConfig.defaults[campo] ??
        CertificadoTextoCampoConfig.padraoGenerico;
  }

  double _ptToPreviewMm(double pt) {
    if (pt <= 0) return pt;

    // Compatibilidade: se vier config antiga na escala visual, mantém.
    if (pt < 9.0) return pt;

    // O SVG trabalha em mm; 3pt ≈ 1 unidade visual usada no certificado.
    return pt / 3.0;
  }

  Color _colorFromHex(String value, Color fallback) {
    final clean = value.trim().replaceAll('#', '').toUpperCase();

    if (!RegExp(r'^[0-9A-F]{6}$').hasMatch(clean)) return fallback;

    return Color(int.parse('FF$clean', radix: 16));
  }

  TextAlign _textAlignFromConfig(String value) {
    final clean = value.trim().toLowerCase();

    if (clean == 'left' || clean == 'esquerda' || clean == 'start') {
      return TextAlign.left;
    }

    if (clean == 'right' || clean == 'direita' || clean == 'end') {
      return TextAlign.right;
    }

    return TextAlign.center;
  }

  FontWeight _fontWeightFromConfig(CertificadoTextoCampoConfig config) {
    return config.negrito ? FontWeight.w900 : FontWeight.w500;
  }

  String _textoAplicado(String value, CertificadoTextoCampoConfig config) {
    return config.aplicarCaixa(value);
  }

  String _applyTextCase(String value, String textCase, bool uppercase) {
    final clean = value.trim();
    if (clean.isEmpty) return '';

    switch (textCase) {
      case 'lower':
        return clean.toLowerCase();
      case 'title':
        return _toTitleCase(clean);
      case 'none':
        return clean;
      case 'upper':
      default:
        return uppercase ? clean.toUpperCase() : clean;
    }
  }

  String _toTitleCase(String value) {
    final lower = value.toLowerCase();

    return lower.replaceAllMapped(
      RegExp(r'(^|[\s\-/])([a-záàâãäéèêëíìîïóòôõöúùûüç])'),
      (match) {
        final prefix = match.group(1) ?? '';
        final letter = match.group(2) ?? '';
        return '$prefix${letter.toUpperCase()}';
      },
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

    final cfgNome = _textoConfig(CertificadoTextoCampoConfig.campoNome);
    final cfgCpf = _textoConfig(CertificadoTextoCampoConfig.campoCpf);
    final cfgGraduacao = _textoConfig(
      CertificadoTextoCampoConfig.campoGraduacao,
    );
    final cfgFrase = _textoConfig(CertificadoTextoCampoConfig.campoFrase);
    final cfgAssinaturaNome = _textoConfig(
      CertificadoTextoCampoConfig.campoAssinaturaNome,
    );
    final cfgAssinaturaApelido = _textoConfig(
      CertificadoTextoCampoConfig.campoAssinaturaApelido,
    );
    final cfgLocalData = _textoConfig(
      CertificadoTextoCampoConfig.campoLocalData,
    );

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
      String textCase = 'upper',
      bool autoAjustar = true,
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
                _applyTextCase(clean, textCase, uppercase),
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
      String textCase = 'upper',
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
            child: _PreviewParagraphText(
              text: _applyTextCase(clean, textCase, uppercase),
              textAlign: align,
              maxLines: maxLines,
              lineHeight: height,
              style: TextStyle(
                color: color,
                fontSize: fontSizeMm * scale,
                fontWeight: fontWeight,
                fontFamily: fontFamily,
                height: 1.0,
              ),
            ),
          ),
        ),
      );
    }

    bool blocoAtivo(String id) => widget.studioConfig?.blocoAtivo(id) ?? true;

    // As linhas pontilhadas ficam 100% por conta do SVG original.
    // O overlay daqui desenha apenas os textos.

    // Nome do aluno: maior, Arial Bold, base inferior do retângulo guia.
    if (blocoAtivo('nome')) {
      addSingleLine(
      slotId: CertificadoSlotIds.alunoNome,
      value: data.alunoNome,
      fontSizeMm: _ptToPreviewMm(cfgNome.tamanho),
      fontWeight: _fontWeightFromConfig(cfgNome),
      color: _colorFromHex(cfgNome.corHex, vinhoTexto),
      align: _textAlignFromConfig(cfgNome.alinhamento),
      fontFamily: cfgNome.fonte,
      letterSpacingMm: 0.015,
      uppercase: cfgNome.uppercase,
      textCase: cfgNome.textCase,
      topOffsetMm: -1.0 + cfgNome.verticalOffsetMm,
      bottomOffsetMm: 1.08,
    );
    }

    // CPF só aparece nos modelos que exigem CPF.
    // No certificado simples, mesmo que o aluno tenha CPF cadastrado, não desenha.
    //
    // O PDF direto usa fallback manual porque alguns SVGs têm a guia do CPF
    // sem id="cpf". A prévia segue a mesma lógica para ficar fiel à impressão.
    if (blocoAtivo('cpf') && widget.tipo.exigeCpf && data.cpfFormatado.isNotEmpty) {
      final cpfSlotOriginal = slots[CertificadoSlotIds.cpf];

      final cpfSlot =
          cpfSlotOriginal ??
          const CertificadoSlotModel(
            id: CertificadoSlotIds.cpf,
            x: 132.9,
            y: 90.62,
            width: 47.0,
            height: 5.7,
          );

      widgets.add(
        _PositionedSlotText(
          slot: cpfSlot,
          scale: scale,
          topOffset:
              ((cpfSlotOriginal == null ? 0.0 : -0.42) +
                  cfgCpf.verticalOffsetMm) *
              scale,
          leftOffset: cpfSlotOriginal == null ? 0 : 1.1 * scale,
          widthExtra: cpfSlotOriginal == null ? 0 : 10.0 * scale,
          heightExtra: cpfSlotOriginal == null ? 0 : 1.7 * scale,
          child: Align(
            alignment: centerAlignmentFromTextAlign(
              _textAlignFromConfig(cfgCpf.alinhamento),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: centerAlignmentFromTextAlign(
                _textAlignFromConfig(cfgCpf.alinhamento),
              ),
              child: Text(
                _textoAplicado(data.cpfFormatado, cfgCpf),
                maxLines: 1,
                textAlign: _textAlignFromConfig(cfgCpf.alinhamento),
                style: TextStyle(
                  color: _colorFromHex(cfgCpf.corHex, vinhoTexto),
                  fontSize: _ptToPreviewMm(cfgCpf.tamanho) * scale,
                  fontWeight: _fontWeightFromConfig(cfgCpf),
                  fontFamily: cfgCpf.fonte,
                  height: cfgCpf.lineHeight,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Graduação: 3mm para a direita, Arial Bold, cor do nome.
    if (blocoAtivo('graduacao')) {
      addSingleLine(
      slotId: CertificadoSlotIds.graduacaoNova,
      value: _graduacaoExibidaComGenero(data.graduacaoNova, data),
      fontSizeMm: _ptToPreviewMm(cfgGraduacao.tamanho),
      fontWeight: _fontWeightFromConfig(cfgGraduacao),
      color: _colorFromHex(cfgGraduacao.corHex, vinhoTexto),
      align: _textAlignFromConfig(cfgGraduacao.alinhamento),
      fontFamily: cfgGraduacao.fonte,
      uppercase: cfgGraduacao.uppercase,
      textCase: cfgGraduacao.textCase,
      leftOffsetMm: 3.0,
      widthExtraMm: -3.0,
      topOffsetMm: cfgGraduacao.verticalOffsetMm,
      bottomOffsetMm: 0.10,
    );
    }

    // Frase: agora alinha no topo do retângulo, não no centro.
    // Ela precisa ocupar visualmente a faixa como no modelo do Photoshop.
    if (blocoAtivo('frase')) {
      addMultiLine(
      slotId: CertificadoSlotIds.frase,
      value: data.fraseFinal(
        tipo: widget.tipo,
        tituloGraduacao: _tituloParaTipo(widget.tipo),
        corda: data.graduacaoNova,
      ),
      fontSizeMm: _ptToPreviewMm(cfgFrase.tamanho),
      fontWeight: _fontWeightFromConfig(cfgFrase),
      color: _colorFromHex(cfgFrase.corHex, vinhoTexto),
      align: _textAlignFromConfig(cfgFrase.alinhamento),
      fontFamily: cfgFrase.fonte,
      height: cfgFrase.lineHeight,
      uppercase: cfgFrase.uppercase,
      textCase: cfgFrase.textCase,
      alignTop: true,
      topOffsetMm: 0.55 + cfgFrase.verticalOffsetMm,
      leftOffsetMm: -2.0,
      widthExtraMm: 4.0,
    );
    }

    if (blocoAtivo('assinatura_nome') || blocoAtivo('assinatura_apelido'))
    { for (var i = 0; i < 5; i++) {
      final assinatura = i < data.assinaturas.length
          ? data.assinaturas[i]
          : null;
      if (assinatura == null) continue;

      final numero = i + 1;

      if (blocoAtivo('assinatura_nome')) {
        addSingleLine(
        slotId: 'assinatura$numero',
        value: assinatura.nome,
        fontSizeMm: _ptToPreviewMm(cfgAssinaturaNome.tamanho),
        fontWeight: _fontWeightFromConfig(cfgAssinaturaNome),
        color: _colorFromHex(cfgAssinaturaNome.corHex, vinhoTexto),
        align: _textAlignFromConfig(cfgAssinaturaNome.alinhamento),
        fontFamily: cfgAssinaturaNome.fonte,
        uppercase: cfgAssinaturaNome.uppercase,
        textCase: cfgAssinaturaNome.textCase,
        topOffsetMm: cfgAssinaturaNome.verticalOffsetMm,
        bottomOffsetMm: 0.05,
      );
      }

      if (blocoAtivo('assinatura_apelido')) {
        addSingleLine(
        slotId: 'apelido$numero',
        value: assinatura.apelido,
        fontSizeMm: _ptToPreviewMm(cfgAssinaturaApelido.tamanho),
        fontWeight: _fontWeightFromConfig(cfgAssinaturaApelido),
        color: _colorFromHex(cfgAssinaturaApelido.corHex, vinhoTexto),
        align: _textAlignFromConfig(cfgAssinaturaApelido.alinhamento),
        fontFamily: cfgAssinaturaApelido.fonte,
        uppercase: cfgAssinaturaApelido.uppercase,
        textCase: cfgAssinaturaApelido.textCase,
        topOffsetMm: cfgAssinaturaApelido.verticalOffsetMm,
        bottomOffsetMm: 0.05,
      );
      }
    } }

    if (blocoAtivo('local_data')) {
      addSingleLine(
      slotId: CertificadoSlotIds.localData,
      value: data.localData,
      fontSizeMm: _ptToPreviewMm(cfgLocalData.tamanho),
      fontWeight: _fontWeightFromConfig(cfgLocalData),
      color: _colorFromHex(cfgLocalData.corHex, vinhoTexto),
      align: _textAlignFromConfig(cfgLocalData.alinhamento),
      fontFamily: cfgLocalData.fonte,
      letterSpacingMm: 0.01,
      uppercase: cfgLocalData.uppercase,
      textCase: cfgLocalData.textCase,
      topOffsetMm: cfgLocalData.verticalOffsetMm,
      bottomOffsetMm: 0.08,
    );
    }

    return widgets;
  }

  String _graduacaoExibidaComGenero(
    String graduacao,
    CertificadoPreviewData data,
  ) {
    if (!data.sexoFeminino) return graduacao;

    var out = graduacao.trim().toUpperCase();
    if (out.isEmpty) return out;

    final substituicoes = <String, String>{
      'CONTRA-MESTRE': 'CONTRA-MESTRA',
      'CONTRA MESTRE': 'CONTRA MESTRA',
      'CONTRAMESTRE': 'CONTRAMESTRA',
      'C. MESTRE': 'C. MESTRA',
      'C.MESTRE': 'C.MESTRA',
      'CM. MESTRE': 'CM. MESTRA',
      'CM.MESTRE': 'CM.MESTRA',
      'MONITOR': 'MONITORA',
      'INSTRUTOR': 'INSTRUTORA',
      'PROFESSOR': 'PROFESSORA',
      'MESTRE': 'MESTRA',
      'FORMADO': 'FORMADA',
      'GRADUADO': 'GRADUADA',
    };

    for (final entry in substituicoes.entries) {
      out = out.replaceAll(
        RegExp('(?<![A-ZÀ-Ú])${RegExp.escape(entry.key)}(?![A-ZÀ-Ú])'),
        entry.value,
      );
    }

    return out;
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

  Widget _buildPreviewFrame({
    required Widget Function(
      double innerWidth,
      double innerHeight,
      double scale,
    )
    childBuilder,
    GlobalKey? exportKey,
  }) {
    final t = context.uai;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = widget.maxHeight ?? 520.0;
        final pageW = _documentWidth;
        final pageH = _documentHeight;
        final calculatedHeight = (constraints.maxWidth / (pageW / pageH)).clamp(
          180.0,
          maxHeight,
        );

        // Esse padding é apenas visual no painel.
        // A exportação NÃO captura esse padding, nem a borda arredondada do card.
        const padding = 8.0;
        final innerWidth = constraints.maxWidth - (padding * 2);
        final innerHeight = calculatedHeight - (padding * 2);
        final scaleX = innerWidth / pageW;
        final scaleY = innerHeight / pageH;
        final scale = scaleX < scaleY ? scaleX : scaleY;

        final certificadoLimpo = SizedBox(
          width: pageW * scale,
          height: pageH * scale,
          child: childBuilder(pageW * scale, pageH * scale, scale),
        );

        final conteudo = exportKey == null
            ? certificadoLimpo
            : RepaintBoundary(key: exportKey, child: certificadoLimpo);

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

class _PreviewParagraphText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final int? maxLines;
  final double lineHeight;

  const _PreviewParagraphText({
    required this.text,
    required this.style,
    required this.textAlign,
    required this.lineHeight,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final lines = _wrap(text, style: style, maxWidth: constraints.maxWidth);

        final visibleLines = maxLines == null
            ? lines
            : lines.take(maxLines!.clamp(0, lines.length)).toList();

        final fontSize = style.fontSize ?? 12;
        final lineStep = fontSize * (lineHeight <= 0 ? 1.16 : lineHeight);

        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < visibleLines.length; i++)
                Positioned(
                  left: 0,
                  right: 0,
                  top: i * lineStep,
                  child: Text(
                    visibleLines[i],
                    textAlign: textAlign,
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    style: style,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  List<String> _wrap(
    String value, {
    required TextStyle style,
    required double maxWidth,
  }) {
    final words = value.trim().replaceAll(RegExp(r'\s+'), ' ').split(' ');
    final lines = <String>[];
    var current = '';

    for (final word in words) {
      final candidate = current.isEmpty ? word : '$current $word';

      if (_fits(candidate, style, maxWidth) || current.isEmpty) {
        current = candidate;
      } else {
        lines.add(current);
        current = word;
      }
    }

    if (current.isNotEmpty) lines.add(current);
    return lines;
  }

  bool _fits(String value, TextStyle style, double maxWidth) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: double.infinity);

    return painter.width <= maxWidth;
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
  final Uint8List? basePreviewBytes;
  final Map<String, CertificadoSlotModel> slots;
  final List<_CertificadoStudioLayerPayload> camadas;

  const _CertificadoPreviewPayload({
    required this.svg,
    this.basePreviewBytes,
    required this.slots,
    this.camadas = const [],
  });
}

class _CertificadoStudioLayerPayload {
  final CertificadoStudioLayer layer;
  final String? svg;
  final Uint8List? previewBytes;

  const _CertificadoStudioLayerPayload({
    required this.layer,
    this.svg,
    this.previewBytes,
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

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final accent = _ensureVisible(context, color);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withAlpha(26), t.cardAlt),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withAlpha(46)),
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


class _StudioQrPreviewPainter extends CustomPainter {
  final Color foreground;
  const _StudioQrPreviewPainter({required this.foreground});

  @override
  void paint(Canvas canvas, Size size) {
    const n = 29;
    final cell = size.shortestSide / n;
    final paint = Paint()..color = foreground;

    bool finder(int r, int c, int top, int left) {
      final rr = r - top, cc = c - left;
      if (rr < 0 || cc < 0 || rr >= 7 || cc >= 7) return false;
      final outer = rr == 0 || cc == 0 || rr == 6 || cc == 6;
      final inner = rr >= 2 && rr <= 4 && cc >= 2 && cc <= 4;
      return outer || inner;
    }

    bool reserved(int r, int c) =>
        (r < 8 && c < 8) || (r < 8 && c >= n - 8) || (r >= n - 8 && c < 8);

    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        var on = finder(r, c, 0, 0) || finder(r, c, 0, n - 7) || finder(r, c, n - 7, 0);
        if (!on && !reserved(r, c)) {
          // Matriz determinística de prévia. O QR oficial será gerado somente na emissão V2.
          final v = (r * 17 + c * 31 + r * c * 7 + (r ^ c) * 11) % 13;
          on = v < 6 || ((r + c) % 11 == 0);
        }
        if (on) {
          canvas.drawRect(
            Rect.fromLTWH(c * cell, r * cell, cell + .15, cell + .15),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StudioQrPreviewPainter oldDelegate) =>
      oldDelegate.foreground != foreground;
}
