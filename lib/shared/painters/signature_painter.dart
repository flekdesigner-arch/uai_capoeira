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
      if (stroke.length == 1) {
        canvas.drawCircle(
          stroke.first,
          strokeWidth / 2,
          Paint()..color = color,
        );
      }
      for (int i = 0; i < stroke.length - 1; i++) {
        final p1 = stroke[i];
        final p2 = stroke[i + 1];
        canvas.drawLine(p1, p2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant SignaturePainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

// 🔥 CRIAR UM CONTROLLER PARA A ASSINATURA
class SignatureController extends ChangeNotifier {
  final List<List<Offset>> _points = [];
  List<Offset>? _currentStroke;

  List<List<Offset>> get points => List.unmodifiable([
    ..._points.map((s) => List<Offset>.unmodifiable(s)),
    if (_currentStroke != null) List<Offset>.unmodifiable(_currentStroke!),
  ]);
  bool get hasSignature =>
      _points.any((stroke) => stroke.length >= 2) ||
      (_currentStroke?.length ?? 0) >= 2;

  void addPoint(Offset point) {
    if (_currentStroke == null) {
      _currentStroke = [point];
    } else {
      _currentStroke!.add(point);
    }
    notifyListeners();
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
  int? _activePointer;
  @override
  Widget build(BuildContext context) {
    Offset bounded(Offset p) {
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return p;
      return Offset(
        p.dx.clamp(0.0, box.size.width),
        p.dy.clamp(0.0, box.size.height),
      );
    }

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        if (_activePointer != null) return;
        _activePointer = e.pointer;
        widget.controller.addPoint(bounded(e.localPosition));
      },
      onPointerMove: (e) {
        if (_activePointer == e.pointer) {
          widget.controller.addPoint(bounded(e.localPosition));
        }
      },
      onPointerUp: (e) {
        if (_activePointer == e.pointer) {
          widget.controller.endStroke();
          _activePointer = null;
        }
      },
      onPointerCancel: (e) {
        if (_activePointer == e.pointer) {
          widget.controller.endStroke();
          _activePointer = null;
        }
      },
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
    );
  }
}
