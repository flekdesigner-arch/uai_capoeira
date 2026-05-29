import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:typed_data';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/shared/painters/signature_painter.dart';
import 'package:uai_capoeira/shared/services/signature_service.dart';

class SignatureScreen extends StatefulWidget {
  final String inscricaoId;
  final String nomeResponsavel;
  final String nomeAluno;
  final Function(Uint8List imageBytes) onConfirm;

  const SignatureScreen({
    super.key,
    required this.inscricaoId,
    required this.nomeResponsavel,
    required this.nomeAluno,
    required this.onConfirm,
  });

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  final SignatureService _signatureService = SignatureService();
  late SignatureController _signatureController;

  bool _isLoading = false;
  String? _erroMensagem;

  @override
  void initState() {
    super.initState();

    _signatureController = SignatureController();
    _signatureController.addListener(_onSignatureChanged);

    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    _signatureController.removeListener(_onSignatureChanged);
    _signatureController.dispose();

    SystemChrome.setPreferredOrientations(DeviceOrientation.values);

    super.dispose();
  }

  void _onSignatureChanged() {
    if (!mounted) return;
    setState(() {});
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

  SystemUiOverlayStyle _overlayStyleFor(Color background) {
    final isDark = background.computeLuminance() < 0.45;

    return isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;
  }

  Future<void> _confirmarAssinatura() async {
    if (!_signatureController.hasSignature) {
      setState(() {
        _erroMensagem = 'Faça sua assinatura no quadro antes de continuar.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _erroMensagem = null;
    });

    try {
      final points = _signatureController.points;

      if (points.isEmpty) {
        throw Exception('Nenhum traço encontrado');
      }

      final imageData = await _signatureService.signatureToImage(
        context,
        points,
        backgroundColor: Colors.white,
        penColor: Colors.black,
        padding: 20.0,
      );

      if (imageData == null) {
        throw Exception('Erro ao processar imagem da assinatura');
      }

      widget.onConfirm(imageData);

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _erroMensagem =
        'Erro: ${e.toString().replaceAll('Exception:', '').trim()}';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _limparAssinatura() {
    if (_isLoading) return;

    _signatureController.clear();

    setState(() {
      _erroMensagem = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return PopScope(
      canPop: !_isLoading,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: _overlayStyleFor(isLandscape ? Colors.white : t.background),
        child: isLandscape ? _buildLandscapePremium() : _buildPortraitPremium(),
      ),
    );
  }

  // ============================================================
  // MODO EM PÉ
  // ============================================================
  Widget _buildPortraitPremium() {
    final t = context.uai;
    final hasSignature = _signatureController.hasSignature;
    final onPrimary = _readableOn(t.primary);

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text(
          'Assinatura',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
        backgroundColor: t.primary,
        foregroundColor: onPrimary,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Limpar assinatura',
            onPressed: _isLoading ? null : _limparAssinatura,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildRotateTip(),
            if (_erroMensagem != null) _buildErrorBox(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: _buildSignatureBoard(
                  borderRadius: t.cardRadius + 2,
                  showTopStatus: true,
                  showBigHint: true,
                ),
              ),
            ),
            _buildSignerCompact(),
            _buildBottomBarPortrait(hasSignature),
          ],
        ),
      ),
    );
  }

  Widget _buildRotateTip() {
    final t = context.uai;
    final accent = _ensureVisible(t.warning, t.card);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.08), t.card),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(0.16)),
      ),
      child: Row(
        children: [
          Icon(Icons.screen_rotation_rounded, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Dica: vire o celular de lado para assinar com mais espaço.',
              style: TextStyle(
                color: accent,
                fontSize: 12.5,
                height: 1.25,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // MODO DEITADO PREMIUM
  // ============================================================
  Widget _buildLandscapePremium() {
    final hasSignature = _signatureController.hasSignature;
    final padding = MediaQuery.of(context).padding;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                8 + padding.left,
                8 + padding.top,
                8 + padding.right,
                8 + padding.bottom,
              ),
              child: _buildSignatureBoard(
                borderRadius: 22,
                showTopStatus: false,
                showBigHint: true,
                landscapeFull: true,
              ),
            ),
          ),
          Positioned(
            left: 18 + padding.left,
            top: 16 + padding.top,
            child: _floatingGlassChip(
              icon:
              hasSignature ? Icons.check_circle_rounded : Icons.draw_rounded,
              label: hasSignature ? 'Assinatura detectada' : 'Assine no quadro',
              color: hasSignature ? context.uai.success : context.uai.primary,
              forceLightCard: true,
            ),
          ),
          Positioned(
            right: 18 + padding.right,
            top: 16 + padding.top,
            child: _floatingNameChip(),
          ),
          if (_erroMensagem != null)
            Positioned(
              left: 18 + padding.left,
              right: 18 + padding.right,
              top: 62 + padding.top,
              child: _buildErrorBox(compact: true, forceLight: true),
            ),
          Positioned(
            left: 18 + padding.left,
            right: 18 + padding.right,
            bottom: 16 + padding.bottom,
            child: _buildFloatingActionsLandscape(hasSignature),
          ),
        ],
      ),
    );
  }

  Widget _floatingGlassChip({
    required IconData icon,
    required String label,
    required Color color,
    bool forceLightCard = false,
  }) {
    final t = context.uai;
    final card = forceLightCard ? Colors.white : t.card;
    final accent = _ensureVisible(color, card);
    final textColor = forceLightCard ? const Color(0xFF111827) : t.textPrimary;

    return Container(
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: forceLightCard ? Colors.white.withOpacity(0.94) : t.card,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withOpacity(0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 18),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _floatingNameChip() {
    final responsavel = widget.nomeResponsavel.trim().isEmpty
        ? 'Signatário'
        : widget.nomeResponsavel.trim();

    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.62),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.person_rounded, color: Colors.white, size: 16),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              responsavel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BOARD / PRANCHETA
  // ============================================================
  Widget _buildSignatureBoard({
    required double borderRadius,
    required bool showTopStatus,
    required bool showBigHint,
    bool landscapeFull = false,
  }) {
    final t = context.uai;
    final hasSignature = _signatureController.hasSignature;
    final success = _ensureVisible(t.success, Colors.white);
    final primary = _ensureVisible(t.primary, Colors.white);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(borderRadius),
      clipBehavior: Clip.antiAlias,
      elevation: landscapeFull ? 0 : 3,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: hasSignature ? success : const Color(0xFFD1D5DB),
            width: hasSignature ? 2.2 : 1.2,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: SignaturePad(
                  key: ValueKey(
                    'signature-pad-${hasSignature ? 'signed' : 'empty'}',
                  ),
                  controller: _signatureController,
                  penColor: Colors.black,
                  strokeWidth: landscapeFull ? 3.6 : 3.2,
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _SignatureGuidePainter(
                    showCenterText: showBigHint && !hasSignature,
                    centerText: 'Assine aqui',
                    isLandscape: landscapeFull,
                    guideColor: Colors.grey.withOpacity(0.16),
                    baseLineColor: primary.withOpacity(0.18),
                    textColor: Colors.grey.withOpacity(0.28),
                  ),
                ),
              ),
            ),
            if (showTopStatus)
              Positioned(
                left: 12,
                top: 12,
                child: _floatingGlassChip(
                  icon: hasSignature
                      ? Icons.check_circle_rounded
                      : Icons.edit_rounded,
                  label: hasSignature
                      ? 'Assinatura detectada'
                      : 'Aguardando assinatura',
                  color: hasSignature ? t.success : t.primary,
                  forceLightCard: true,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // BOTÕES
  // ============================================================
  Widget _buildBottomBarPortrait(bool hasSignature) {
    final t = context.uai;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: t.surface,
          border: Border(top: BorderSide(color: t.border)),
          boxShadow: t.softShadow,
        ),
        child: Row(
          children: [
            Expanded(child: _cancelButton()),
            const SizedBox(width: 8),
            Expanded(child: _clearButton()),
            const SizedBox(width: 8),
            Expanded(child: _confirmButton(hasSignature)),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingActionsLandscape(bool hasSignature) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 620),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.62),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.20),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(child: _cancelButton(dark: true)),
            const SizedBox(width: 8),
            Expanded(child: _clearButton(dark: true)),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: _confirmButton(hasSignature)),
          ],
        ),
      ),
    );
  }

  Widget _cancelButton({bool dark = false}) {
    final t = context.uai;

    return OutlinedButton.icon(
      onPressed: _isLoading ? null : () => Navigator.pop(context),
      icon: const Icon(Icons.close_rounded, size: 18),
      label: const Text('CANCELAR'),
      style: OutlinedButton.styleFrom(
        foregroundColor: dark ? Colors.white : t.textPrimary,
        side: BorderSide(
          color: dark ? Colors.white.withOpacity(0.32) : t.border,
        ),
        backgroundColor: dark ? Colors.white.withOpacity(0.08) : t.card,
        padding: const EdgeInsets.symmetric(vertical: 13),
        textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.buttonRadius),
        ),
      ),
    );
  }

  Widget _clearButton({bool dark = false}) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, dark ? Colors.black : t.card);

    return OutlinedButton.icon(
      onPressed: _isLoading ? null : _limparAssinatura,
      icon: const Icon(Icons.refresh_rounded, size: 18),
      label: const Text('LIMPAR'),
      style: OutlinedButton.styleFrom(
        foregroundColor: dark ? Colors.white : primary,
        side: BorderSide(
          color: dark ? Colors.white.withOpacity(0.32) : primary.withOpacity(0.22),
        ),
        backgroundColor: dark ? Colors.white.withOpacity(0.08) : t.card,
        padding: const EdgeInsets.symmetric(vertical: 13),
        textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.buttonRadius),
        ),
      ),
    );
  }

  Widget _confirmButton(bool hasSignature) {
    final t = context.uai;
    final bg = hasSignature ? t.success : t.primary;
    final safeBg = _ensureVisible(bg, t.background);

    return ElevatedButton.icon(
      onPressed: _isLoading ? null : _confirmarAssinatura,
      icon: _isLoading
          ? SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: _readableOn(safeBg),
        ),
      )
          : Icon(
        hasSignature ? Icons.check_rounded : Icons.draw_rounded,
        size: 18,
      ),
      label: Text(_isLoading ? 'PREPARANDO...' : 'USAR ASSINATURA'),
      style: ElevatedButton.styleFrom(
        backgroundColor: safeBg,
        foregroundColor: _readableOn(safeBg),
        padding: const EdgeInsets.symmetric(vertical: 13),
        textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.buttonRadius),
        ),
        elevation: 0,
      ),
    );
  }

  // ============================================================
  // INFO / ERRO
  // ============================================================
  Widget _buildSignerCompact() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: _miniInfo(
              icon: Icons.person_rounded,
              label: 'Signatário',
              value: widget.nomeResponsavel,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _miniInfo(
              icon: Icons.child_care_rounded,
              label: 'Aluno',
              value: widget.nomeAluno,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniInfo({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.card);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: primary, size: 18),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: t.textSecondary, fontSize: 10),
                ),
                Text(
                  value.trim().isEmpty ? 'Não informado' : value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 12,
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

  Widget _buildErrorBox({
    bool compact = false,
    bool forceLight = false,
  }) {
    final t = context.uai;
    final card = forceLight ? Colors.white : t.card;
    final danger = _ensureVisible(t.error, card);
    final textColor = forceLight ? const Color(0xFF7F1D1D) : danger;

    return Container(
      margin: compact ? EdgeInsets.zero : const EdgeInsets.fromLTRB(12, 6, 12, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: forceLight
            ? const Color(0xFFFFF1F2).withOpacity(0.96)
            : Color.alphaBlend(danger.withOpacity(0.08), t.card),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: danger.withOpacity(0.18)),
        boxShadow: compact
            ? [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ]
            : null,
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: danger),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              _erroMensagem!,
              style: TextStyle(
                color: textColor,
                fontSize: compact ? 11.5 : 12,
                height: 1.25,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignatureGuidePainter extends CustomPainter {
  final bool showCenterText;
  final String centerText;
  final bool isLandscape;
  final Color guideColor;
  final Color baseLineColor;
  final Color textColor;

  const _SignatureGuidePainter({
    required this.showCenterText,
    required this.centerText,
    required this.isLandscape,
    required this.guideColor,
    required this.baseLineColor,
    required this.textColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = guideColor
      ..strokeWidth = 1;

    final baseLinePaint = Paint()
      ..color = baseLineColor
      ..strokeWidth = 1.5;

    final startX = size.width * 0.07;
    final endX = size.width * 0.93;

    final horizontalCount = isLandscape ? 4 : 5;
    for (int i = 1; i <= horizontalCount; i++) {
      final y = size.height * (i / (horizontalCount + 1));
      canvas.drawLine(Offset(startX, y), Offset(endX, y), linePaint);
    }

    final baseY = size.height * (isLandscape ? 0.68 : 0.70);
    canvas.drawLine(Offset(startX, baseY), Offset(endX, baseY), baseLinePaint);

    final verticalPaint = Paint()
      ..color = guideColor.withOpacity(0.50)
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(size.width * 0.50, size.height * 0.10),
      Offset(size.width * 0.50, size.height * 0.88),
      verticalPaint,
    );

    if (showCenterText) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: centerText,
          style: TextStyle(
            color: textColor,
            fontSize: isLandscape ? 42 : 34,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);

      textPainter.paint(
        canvas,
        Offset(
          (size.width - textPainter.width) / 2,
          (size.height - textPainter.height) / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SignatureGuidePainter oldDelegate) {
    return oldDelegate.showCenterText != showCenterText ||
        oldDelegate.centerText != centerText ||
        oldDelegate.isLandscape != isLandscape ||
        oldDelegate.guideColor != guideColor ||
        oldDelegate.baseLineColor != baseLineColor ||
        oldDelegate.textColor != textColor;
  }
}
