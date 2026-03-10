import 'package:flutter/material.dart';

class SignaturePainter extends CustomPainter {
  final List<List<Offset>> points;
  final Color color;
  final double strokeWidth;

  SignaturePainter({
    required this.points,
    this.color = Colors.black,
    this.strokeWidth = 3.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (var stroke in points) {
      for (int i = 0; i < stroke.length - 1; i++) {
        final p1 = stroke[i];
        final p2 = stroke[i + 1];
        canvas.drawLine(p1, p2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant SignaturePainter oldDelegate) {
    return oldDelegate.points != points;
  }
}

// 🔥 CRIAR UM CONTROLLER PARA A ASSINATURA
class SignatureController extends ChangeNotifier {
  List<List<Offset>> _points = [];
  List<Offset>? _currentStroke;

  List<List<Offset>> get points => List.unmodifiable(_points);
  bool get hasSignature => _points.isNotEmpty;

  void addPoint(Offset point) {
    if (_currentStroke == null) {
      _currentStroke = [point];
    } else {
      _currentStroke!.add(point);
      notifyListeners();
    }
  }

  void endStroke() {
    if (_currentStroke != null) {
      _points.add(_currentStroke!);
      _currentStroke = null;
      notifyListeners();
    }
  }

  void clear() {
    _points.clear();
    _currentStroke = null;
    notifyListeners();
  }
}

class SignaturePad extends StatefulWidget {
  final SignatureController controller;
  final Color penColor;
  final double strokeWidth;

  const SignaturePad({
    super.key,
    required this.controller,
    this.penColor = Colors.black,
    this.strokeWidth = 3.0,
  });

  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (details) {
        widget.controller.addPoint(details.localPosition);
      },
      onPanUpdate: (details) {
        widget.controller.addPoint(details.localPosition);
      },
      onPanEnd: (details) {
        widget.controller.endStroke();
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, child) {
            return CustomPaint(
              painter: SignaturePainter(
                points: widget.controller.points,
                color: widget.penColor,
                strokeWidth: widget.strokeWidth,
              ),
              size: Size.infinite,
            );
          },
        ),
      ),
    );
  }
}