import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/core/theme/app_theme_tokens.dart';

class UaiDynamicLogo extends StatefulWidget {
  final double height;
  final double? width;
  final EdgeInsetsGeometry padding;
  final BoxFit fit;
  final UaiThemeTokens? themeOverride;
  final bool showFallbackText;

  const UaiDynamicLogo({
    super.key,
    this.height = 150,
    this.width,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
    this.fit = BoxFit.contain,
    this.themeOverride,
    this.showFallbackText = true,
  });

  @override
  State<UaiDynamicLogo> createState() => _UaiDynamicLogoState();
}

class _UaiDynamicLogoState extends State<UaiDynamicLogo> {
  static Future<String>? _cachedSvgFuture;

  Future<String> _loadSvg() {
    _cachedSvgFuture ??= rootBundle.loadString(
      'assets/images/logo_uai_tema.svg',
    );
    return _cachedSvgFuture!;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.themeOverride ?? context.uai;

    return Padding(
      padding: widget.padding,
      child: FutureBuilder<String>(
        future: _loadSvg(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            final svg = _aplicarTemaNoLogoUai(snapshot.data!, t);

            return SvgPicture.string(
              svg,
              height: widget.height,
              width: widget.width,
              fit: widget.fit,
              placeholderBuilder: (_) => _buildLoading(t),
            );
          }

          if (snapshot.hasError) {
            return _buildFallback(t);
          }

          return _buildLoading(t);
        },
      ),
    );
  }

  Widget _buildLoading(UaiThemeTokens t) {
    return SizedBox(
      height: widget.height,
      width: widget.width,
      child: Center(
        child: CircularProgressIndicator(color: t.primary),
      ),
    );
  }

  Widget _buildFallback(UaiThemeTokens t) {
    return Container(
      height: widget.height,
      width: widget.width ?? 230,
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.sports_martial_arts,
            size: 58,
            color: t.primary,
          ),
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

  String _aplicarTemaNoLogoUai(String svg, UaiThemeTokens t) {
    final isTemaClassico = _isTemaClassicoUai(t);

    final uaiColor = _colorToHex(t.primary);

    // Pedido especial:
    // Somente no tema UAI Clássico, a faixa da logo fica preta
    // e o texto "CAPOEIRA" fica branco.
    // Nos outros temas, a logo reage ao tema atual.
    final faixaColor = isTemaClassico ? '#111111' : _colorToHex(t.cardAlt);
    final textoColor = isTemaClassico
        ? '#FFFFFF'
        : _colorToHex(_readableOn(t.cardAlt));
    final strokeColor = isTemaClassico ? '#111111' : _colorToHex(t.border);

    var result = svg;

    // O SVG precisa manter cores reais válidas como fallback.
    // Depois este widget troca essas cores pelas cores do tema.
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

    // A faixa e o stroke usam a mesma cor original #373435.
    // Depois do replace geral, garantimos a borda pelo id="faixa".
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

    return result;
  }

  bool _isTemaClassicoUai(UaiThemeTokens t) {
    // Mantém o ajuste independente do AppThemeController.
    // O UAI Clássico usa o vermelho #B71C1C e fundo claro.
    final primaryHex = _colorToHex(t.primary).toUpperCase();
    final backgroundIsLight = t.background.computeLuminance() > 0.55;

    return backgroundIsLight && primaryHex == '#B71C1C';
  }

  String _colorToHex(Color color) {
    return '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : Colors.white;
  }
}