import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:uai_capoeira/models/graduacao_model.dart';

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
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          // SVG base (contorno preto)
          SvgPicture.asset(
            'assets/images/corda.svg',
            fit: BoxFit.contain,
          ),

          // Overlay colorido
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

  CordaColorPainter({required this.cores});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Ajustar escala para o SVG (2963.32 x 4394.18)
    final scaleX = size.width / 2963.32;
    final scaleY = size.height / 4394.18;

    // Desenhar cor1 (parte principal)
    paint.color = cores['cor1']!;
    _drawPathCor1(canvas, paint, scaleX, scaleY);

    // Desenhar cor2 (parte secundária)
    paint.color = cores['cor2']!;
    _drawPathCor2(canvas, paint, scaleX, scaleY);

    // Desenhar ponta1
    paint.color = cores['ponta1']!;
    _drawPathPonta1(canvas, paint, scaleX, scaleY);

    // Desenhar ponta2
    paint.color = cores['ponta2']!;
    _drawPathPonta2(canvas, paint, scaleX, scaleY);
  }

  void _drawPathCor1(Canvas canvas, Paint paint, double sx, double sy) {
    final path = Path();
    path.moveTo(1638.38 * sx, 4213.36 * sy);
    path.lineTo(1569.78 * sx, 4233.04 * sy);
    path.lineTo(1512.27 * sx, 3870.94 * sy);
    path.lineTo(1507.35 * sx, 3738.2 * sy);
    path.lineTo(1580.87 * sx, 3718.73 * sy);
    path.lineTo(1638.38 * sx, 4213.36 * sy);
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawPathCor2(Canvas canvas, Paint paint, double sx, double sy) {
    final path = Path();
    path.moveTo(1565.25 * sx, 3445.73 * sy);
    path.lineTo(1817.02 * sx, 3519.29 * sy);
    path.lineTo(1762.25 * sx, 3749.4 * sy);
    path.lineTo(1512.27 * sx, 3870.94 * sy);
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawPathPonta1(Canvas canvas, Paint paint, double sx, double sy) {
    final path = Path();
    path.moveTo(1735.39 * sx, 3968.78 * sy);
    path.lineTo(1806.99 * sx, 3949.36 * sy);
    path.lineTo(1864.5 * sx, 4333.26 * sy);
    path.lineTo(1735.39 * sx, 3968.78 * sy);
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawPathPonta2(Canvas canvas, Paint paint, double sx, double sy) {
    final path = Path();
    path.moveTo(1638.38 * sx, 4213.36 * sy);
    path.lineTo(1708 * sx, 4193.68 * sy);
    path.lineTo(1762.25 * sx, 3749.4 * sy);
    path.lineTo(1638.38 * sx, 4213.36 * sy);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}