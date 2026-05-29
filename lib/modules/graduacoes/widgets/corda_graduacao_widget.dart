import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/graduacoes/models/graduacao_model.dart';

class CordaGraduacaoWidget extends StatelessWidget {
  final GraduacaoModel graduacao;
  final double width;
  final double height;

  const CordaGraduacaoWidget({
    super.key,
    required this.graduacao,
    this.width = 60,
    this.height = 90,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SvgPicture.asset(
            'assets/images/corda.svg',
            fit: BoxFit.contain,
            placeholderBuilder: (_) {
              return Center(
                child: Icon(
                  Icons.workspace_premium_outlined,
                  color: t.textMuted,
                  size: (width * 0.45).clamp(18.0, 42.0),
                ),
              );
            },
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: CordaColorPainter(
                cores: graduacao.cores,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CordaColorPainter extends CustomPainter {
  final Map<String, Color> cores;

  const CordaColorPainter({required this.cores});

  Color _color(String key) {
    return cores[key] ?? const Color(0xFF9E9E9E);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Escala baseada no SVG original: 2963.32 x 4394.18
    final scaleX = size.width / 2963.32;
    final scaleY = size.height / 4394.18;

    paint.color = _color('cor1');
    _drawPathCor1(canvas, paint, scaleX, scaleY);

    paint.color = _color('cor2');
    _drawPathCor2(canvas, paint, scaleX, scaleY);

    paint.color = _color('ponta1');
    _drawPathPonta1(canvas, paint, scaleX, scaleY);

    paint.color = _color('ponta2');
    _drawPathPonta2(canvas, paint, scaleX, scaleY);
  }

  void _drawPathCor1(Canvas canvas, Paint paint, double sx, double sy) {
    final path = Path()
      ..moveTo(1638.38 * sx, 4213.36 * sy)
      ..lineTo(1569.78 * sx, 4233.04 * sy)
      ..lineTo(1512.27 * sx, 3870.94 * sy)
      ..lineTo(1507.35 * sx, 3738.2 * sy)
      ..lineTo(1580.87 * sx, 3718.73 * sy)
      ..lineTo(1638.38 * sx, 4213.36 * sy)
      ..close();

    canvas.drawPath(path, paint);
  }

  void _drawPathCor2(Canvas canvas, Paint paint, double sx, double sy) {
    final path = Path()
      ..moveTo(1565.25 * sx, 3445.73 * sy)
      ..lineTo(1817.02 * sx, 3519.29 * sy)
      ..lineTo(1762.25 * sx, 3749.4 * sy)
      ..lineTo(1512.27 * sx, 3870.94 * sy)
      ..close();

    canvas.drawPath(path, paint);
  }

  void _drawPathPonta1(Canvas canvas, Paint paint, double sx, double sy) {
    final path = Path()
      ..moveTo(1735.39 * sx, 3968.78 * sy)
      ..lineTo(1806.99 * sx, 3949.36 * sy)
      ..lineTo(1864.5 * sx, 4333.26 * sy)
      ..lineTo(1735.39 * sx, 3968.78 * sy)
      ..close();

    canvas.drawPath(path, paint);
  }

  void _drawPathPonta2(Canvas canvas, Paint paint, double sx, double sy) {
    final path = Path()
      ..moveTo(1638.38 * sx, 4213.36 * sy)
      ..lineTo(1708 * sx, 4193.68 * sy)
      ..lineTo(1762.25 * sx, 3749.4 * sy)
      ..lineTo(1638.38 * sx, 4213.36 * sy)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CordaColorPainter oldDelegate) {
    return oldDelegate.cores != cores;
  }
}
