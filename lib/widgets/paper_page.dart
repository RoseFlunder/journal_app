import 'package:flutter/material.dart';

class PaperPage extends StatelessWidget {
  const PaperPage({
    super.key,
    required this.child,
    this.showRules = true,
    this.showMargin = true,
    this.finite = true,
  });

  final Widget child;
  final bool showRules;
  final bool showMargin;
  final bool finite;

  static const paper = Color(0xFFF2E9D5);
  static const ink = Color(0xFF3B3226);
  static const margin = Color(0xFFC97068);
  static const sage = Color(0xFFB7C1A7);
  static const blush = Color(0xFFF2D7D3);
  static const lilac = Color(0xFFDCCEF4);

  @override
  Widget build(BuildContext context) {
    if (!finite) {
      return DecoratedBox(
        decoration: const BoxDecoration(color: paper),
        child: child,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFBF4), paper],
        ),
        border: Border.all(color: ink.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(3),
        boxShadow: [
          BoxShadow(
            color: ink.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: CustomPaint(
        painter: PaperLinesPainter(
          showRules: showRules,
          showMargin: showMargin,
        ),
        child: child,
      ),
    );
  }
}

class PaperLinesPainter extends CustomPainter {
  const PaperLinesPainter({
    this.showRules = true,
    this.showMargin = true,
  });

  final bool showRules;
  final bool showMargin;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = size.width < 520 ? 22.0 : 34.0;
    final rulePaint = Paint()
      ..color = PaperPage.ink.withValues(alpha: 0.11)
      ..strokeWidth = 0.7;
    final marginPaint = Paint()
      ..color = PaperPage.margin.withValues(alpha: 0.78)
      ..strokeWidth = 1.3;

    if (showRules) {
      for (var y = 82.0; y < size.height - 20; y += 30) {
        canvas.drawLine(
          Offset(inset, y),
          Offset(size.width - 18, y),
          rulePaint,
        );
      }
    }
    if (showMargin && size.width > 100) {
      canvas.drawLine(
        Offset(inset - 10, 0),
        Offset(inset - 10, size.height),
        marginPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant PaperLinesPainter oldDelegate) =>
      showRules != oldDelegate.showRules ||
      showMargin != oldDelegate.showMargin;
}
