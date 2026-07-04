import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_drawing/path_drawing.dart';

import 'package:uai_capoeira/core/logo/uai_logo_config.dart';
import 'package:uai_capoeira/core/logo/uai_logo_service.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/core/theme/app_theme_tokens.dart';

class UaiDynamicLogo extends StatefulWidget {
  final double height;
  final double? width;
  final EdgeInsetsGeometry padding;
  final BoxFit fit;
  final UaiThemeTokens? themeOverride;
  final UaiLogoConfig? logoConfig;
  final bool loadRemoteConfig;
  final String? themeId;
  final bool showFallbackText;

  const UaiDynamicLogo({
    super.key,
    this.height = 150,
    this.width,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
    this.fit = BoxFit.contain,
    this.themeOverride,
    this.logoConfig,
    this.loadRemoteConfig = false,
    this.themeId,
    this.showFallbackText = true,
  });

  @override
  State<UaiDynamicLogo> createState() => _UaiDynamicLogoState();
}

class _UaiDynamicLogoState extends State<UaiDynamicLogo> {
  static Future<String>? _cachedSvgFuture;
  Future<UaiLogoConfig>? _configFuture;

  @override
  void initState() {
    super.initState();
    _syncConfigFuture();
  }

  @override
  void didUpdateWidget(covariant UaiDynamicLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.logoConfig != widget.logoConfig ||
        oldWidget.loadRemoteConfig != widget.loadRemoteConfig ||
        oldWidget.themeId != widget.themeId) {
      _syncConfigFuture();
    }
  }

  Future<String> _loadSvg() {
    _cachedSvgFuture ??= rootBundle.loadString(
      'assets/images/logo_uai_tema.svg',
    );
    return _cachedSvgFuture!;
  }

  void _syncConfigFuture() {
    if (widget.logoConfig != null) {
      _configFuture = Future<UaiLogoConfig>.value(widget.logoConfig);
      return;
    }

    final themeId = widget.themeId?.trim();
    if (widget.loadRemoteConfig && themeId != null && themeId.isNotEmpty) {
      _configFuture = UaiLogoService.instance.loadForTheme(themeId);
      return;
    }

    _configFuture = null;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.themeOverride ?? context.uai;

    return Padding(
      padding: widget.padding,
      child: FutureBuilder<UaiLogoConfig>(
        future: _configFuture,
        builder: (context, configSnapshot) {
          final config = configSnapshot.data ?? widget.logoConfig;
          return FutureBuilder<String>(
            future: _loadSvg(),
            builder: (context, svgSnapshot) {
              if (svgSnapshot.hasData) {
                return _buildLogo(svgSnapshot.data!, t, config);
              }

              if (svgSnapshot.hasError) {
                return _buildFallback(t);
              }

              return _buildLoading(t);
            },
          );
        },
      ),
    );
  }

  Widget _buildLogo(String rawSvg, UaiThemeTokens t, UaiLogoConfig? config) {
    final logoWidth = _logoWidth;
    final svg = _aplicarTemaNoLogoUai(rawSvg, t, config);
    final logo = SvgPicture.string(
      svg,
      height: widget.height,
      width: logoWidth,
      fit: widget.fit,
      placeholderBuilder: (_) => _buildLoading(t),
    );

    final slotClip = config?.hasValidSlotUai == true
        ? _buildSlotUaiClipado(
            pathData: _extrairPathDDoUai(rawSvg) ?? '',
            config: config!,
            height: widget.height,
            width: widget.width,
          )
        : null;

    final ornament = config?.hasValidOrnament == true
        ? _buildOrnamentoLayer(config!)
        : null;

    if (slotClip == null && ornament == null) return logo;

    return SizedBox(
      height: widget.height,
      width: logoWidth,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (slotClip != null) Positioned.fill(child: slotClip),
          Positioned.fill(child: logo),
          if (ornament != null) Positioned.fill(child: ornament),
        ],
      ),
    );
  }

  Widget _buildSlotUaiClipado({
    required String pathData,
    required UaiLogoConfig config,
    required double height,
    required double? width,
  }) {
    if (pathData.trim().isEmpty || config.slotUaiUrl.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final logoWidth = width ?? (height * 2);
    final clipper = _SvgPathClipper(
      pathData: pathData,
      svgViewBoxSize: const Size(5000, 2500),
    );

    return ClipPath(
      clipBehavior: Clip.antiAlias,
      clipper: clipper,
      child: SizedBox(
        width: logoWidth,
        height: height,
        child: Transform.translate(
          offset: Offset(config.slotUaiOffsetX, config.slotUaiOffsetY),
          child: Transform.scale(
            scale: config.slotUaiScale,
            alignment: Alignment.center,
            child: Opacity(
              opacity: config.slotUaiOpacity.clamp(0, 1).toDouble(),
              child: SizedBox.expand(
                child: Image.network(
                  config.slotUaiUrl.trim(),
                  fit: _slotFitFromConfig(config.slotUaiFit),
                  alignment: Alignment.center,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const SizedBox.shrink();
                  },
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOrnamentoLayer(UaiLogoConfig config) {
    return Align(
      alignment: _alignmentFor(config.ornamentoPosicao),
      child: Opacity(
        opacity: config.ornamentoOpacity.clamp(0, 1).toDouble(),
        child: Image.network(
          config.ornamentoUrl.trim(),
          width: config.ornamentoWidth,
          height: config.ornamentoHeight,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
        ),
      ),
    );
  }

  Widget _buildLoading(UaiThemeTokens t) {
    return SizedBox(
      height: widget.height,
      width: _logoWidth,
      child: Center(child: CircularProgressIndicator(color: t.primary)),
    );
  }

  Widget _buildFallback(UaiThemeTokens t) {
    return Container(
      height: widget.height,
      width: _logoWidth,
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.sports_martial_arts, size: 58, color: t.primary),
          if (widget.showFallbackText) ...[
            const SizedBox(height: 10),
            Text(
              'Logo SVG não encontrada',
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _aplicarTemaNoLogoUai(
    String svg,
    UaiThemeTokens t,
    UaiLogoConfig? config,
  ) {
    final isTemaClassico = _isTemaClassicoUai(t);
    final hasCustomConfig =
        config != null && config.ativo && config.usarLogoPersonalizada;

    final uaiColor = hasCustomConfig
        ? UaiLogoConfig.sanitizeHexColor(config.overrideUai) ??
              _colorToHex(t.primary)
        : _colorToHex(t.primary);

    final defaultFaixaColor = isTemaClassico
        ? '#111111'
        : _colorToHex(t.cardAlt);
    final defaultTextoColor = isTemaClassico
        ? '#FFFFFF'
        : _colorToHex(_readableOn(t.cardAlt));
    final defaultStrokeColor = isTemaClassico
        ? '#111111'
        : _colorToHex(t.border);

    final faixaColor = hasCustomConfig
        ? UaiLogoConfig.sanitizeHexColor(config.overrideFaixa) ??
              defaultFaixaColor
        : defaultFaixaColor;
    final textoColor = hasCustomConfig
        ? UaiLogoConfig.sanitizeHexColor(config.overrideCapoeira) ??
              defaultTextoColor
        : defaultTextoColor;
    final strokeColor = hasCustomConfig
        ? UaiLogoConfig.sanitizeHexColor(config.overrideStrokeFaixa) ??
              defaultStrokeColor
        : defaultStrokeColor;

    var result = svg;

    final replacements = <String, String>{
      '#FF0000': uaiColor,
      '#ff0000': uaiColor,
      'red': uaiColor,
      '#373435': faixaColor,
      '#FEFEFE': textoColor,
      '#fefefe': textoColor,
    };

    replacements.forEach((from, to) {
      result = result.replaceAll(from, to);
    });

    result = result.replaceFirstMapped(
      RegExp(r'(<polygon[^>]*id="faixa"[^>]*)(/?>)', caseSensitive: false),
      (match) {
        var tag = match.group(1) ?? '';
        final close = match.group(2) ?? '>';

        if (RegExp(r'\sstroke="[^"]*"').hasMatch(tag)) {
          tag = tag.replaceFirst(
            RegExp(r'\sstroke="[^"]*"'),
            ' stroke="$strokeColor"',
          );
        } else {
          tag = '$tag stroke="$strokeColor"';
        }

        return '$tag$close';
      },
    );

    if (config?.hasValidSlotUai == true) {
      result = _aplicarOverlaySlotUaiNoSvg(result);
    }

    return result;
  }

  String _aplicarOverlaySlotUaiNoSvg(String svg) {
    return svg.replaceFirstMapped(
      RegExp(
        r'(<path\b[^>]*\bid="uai"[^>]*)(fill="[^"]*")([^>]*)(/?>)',
        caseSensitive: false,
        dotAll: true,
      ),
      (match) {
        final beforeFill = match.group(1) ?? '';
        final fillPart = match.group(2) ?? '';
        final afterFill = match.group(3) ?? '';
        final close = match.group(4) ?? '>';

        final updatedFill = fillPart.contains('fill-opacity="')
            ? fillPart.replaceFirst(
                RegExp(r'fill-opacity="[^"]*"', caseSensitive: false),
                'fill-opacity="0.18"',
              )
            : '$fillPart fill-opacity="0.18"';

        return '$beforeFill$updatedFill$afterFill$close';
      },
    );
  }

  String? _extrairPathDDoUai(String svg) {
    final match = RegExp(
      r'<path\b[^>]*\bid="uai"[^>]*\bd="([^"]+)"[^>]*/?>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(svg);
    return match?.group(1);
  }

  BoxFit _slotFitFromConfig(String value) {
    switch (value) {
      case 'contain':
        return BoxFit.contain;
      case 'fill':
        return BoxFit.fill;
      case 'cover':
      default:
        return BoxFit.cover;
    }
  }

  double get _logoWidth => widget.width ?? (widget.height * 2);

  bool _isTemaClassicoUai(UaiThemeTokens t) {
    final primaryHex = _colorToHex(t.primary).toUpperCase();
    final backgroundIsLight = t.background.computeLuminance() > 0.55;

    return backgroundIsLight && primaryHex == '#B71C1C';
  }

  String _colorToHex(Color color) {
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : Colors.white;
  }

  Alignment _alignmentFor(String position) {
    switch (position) {
      case 'topLeft':
        return Alignment.topLeft;
      case 'bottomLeft':
        return Alignment.bottomLeft;
      case 'bottomRight':
        return Alignment.bottomRight;
      case 'center':
        return Alignment.center;
      case 'topCenter':
        return Alignment.topCenter;
      case 'bottomCenter':
        return Alignment.bottomCenter;
      case 'topRight':
      default:
        return Alignment.topRight;
    }
  }
}

class _SvgPathClipper extends CustomClipper<Path> {
  final String pathData;
  final Size svgViewBoxSize;

  const _SvgPathClipper({required this.pathData, required this.svgViewBoxSize});

  @override
  Path getClip(Size size) {
    final originalPath = parseSvgPathData(pathData);
    final scaleX = size.width / svgViewBoxSize.width;
    final scaleY = size.height / svgViewBoxSize.height;

    final matrix = Matrix4.diagonal3Values(scaleX, scaleY, 1);
    return originalPath.transform(matrix.storage);
  }

  @override
  bool shouldReclip(covariant _SvgPathClipper oldClipper) {
    return oldClipper.pathData != pathData ||
        oldClipper.svgViewBoxSize != svgViewBoxSize;
  }
}
