import 'dart:math' as math;

import 'package:flutter/material.dart';

class RetroGauge extends StatelessWidget {
  final String label;
  final String unit;
  final double? value;
  final double min;
  final double max;
  final Color color;

  const RetroGauge({
    super.key,
    required this.label,
    required this.unit,
    required this.value,
    required this.min,
    required this.max,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayValue = value;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 1.3,
          child: CustomPaint(
            painter: _RetroGaugePainter(
              theme: theme,
              value: displayValue,
              min: min,
              max: max,
              color: color,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayValue == null ? '--' : displayValue.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    unit,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RetroGaugePainter extends CustomPainter {
  final ThemeData theme;
  final double? value;
  final double min;
  final double max;
  final Color color;

  _RetroGaugePainter({
    required this.theme,
    required this.value,
    required this.min,
    required this.max,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = math.max(6.0, size.shortestSide * 0.06);
    final outer = Rect.fromLTWH(
      stroke,
      stroke,
      size.width - stroke * 2,
      size.height - stroke * 2,
    );

    // Gauge is a semi-circle (top half).
    const startAngle = math.pi;
    const sweepAngle = math.pi;

    final bgArc = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    final fgArc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(outer, startAngle, sweepAngle, false, bgArc);

    final v = value;
    final clamped = v == null ? null : v.clamp(min, max).toDouble();
    if (clamped != null) {
      final t = (clamped - min) / (max - min);
      canvas.drawArc(outer, startAngle, sweepAngle * t, false, fgArc);
    }

    // Ticks
    final tickPaint = Paint()
      ..color = Colors.grey.shade600
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, stroke * 0.22);

    final center = Offset(size.width / 2, size.height / 2);
    final radius = outer.width / 2;

    for (int i = 0; i <= 10; i++) {
      final tt = i / 10.0;
      final angle = startAngle + sweepAngle * tt;

      final isMajor = i % 2 == 0;
      final tickLen = isMajor ? radius * 0.16 : radius * 0.10;

      final p1 = center + Offset(math.cos(angle), math.sin(angle)) * (radius - stroke * 0.5);
      final p2 = center + Offset(math.cos(angle), math.sin(angle)) * (radius - stroke * 0.5 - tickLen);
      canvas.drawLine(p1, p2, tickPaint);
    }

    // Needle
    if (clamped != null) {
      final t = (clamped - min) / (max - min);
      final angle = startAngle + sweepAngle * t;

      final needlePaint = Paint()
        ..color = theme.colorScheme.error
        ..strokeWidth = math.max(2.0, stroke * 0.26)
        ..strokeCap = StrokeCap.round;

      final needleStart = center + Offset(0, radius * 0.18);
      final needleEnd = center + Offset(math.cos(angle), math.sin(angle)) * (radius * 0.80);

      canvas.drawLine(needleStart, needleEnd, needlePaint);

      final hubPaint = Paint()..color = theme.colorScheme.onSurface.withOpacity(0.8);
      canvas.drawCircle(needleStart, math.max(4.0, stroke * 0.45), hubPaint);
    }

    // Min/Max labels
    _drawText(
      canvas,
      text: min.toStringAsFixed(0),
      at: center + Offset(-radius * 0.78, radius * 0.34),
      color: Colors.grey.shade600,
      fontSize: math.max(10.0, size.shortestSide * 0.08),
      align: TextAlign.left,
    );
    _drawText(
      canvas,
      text: max.toStringAsFixed(0),
      at: center + Offset(radius * 0.78, radius * 0.34),
      color: Colors.grey.shade600,
      fontSize: math.max(10.0, size.shortestSide * 0.08),
      align: TextAlign.right,
    );
  }

  void _drawText(
    Canvas canvas, {
    required String text,
    required Offset at,
    required Color color,
    required double fontSize,
    required TextAlign align,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout();

    Offset offset;
    switch (align) {
      case TextAlign.right:
        offset = Offset(at.dx - tp.width, at.dy - tp.height / 2);
        break;
      case TextAlign.center:
        offset = Offset(at.dx - tp.width / 2, at.dy - tp.height / 2);
        break;
      default:
        offset = Offset(at.dx, at.dy - tp.height / 2);
        break;
    }

    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _RetroGaugePainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.min != min ||
        oldDelegate.max != max ||
        oldDelegate.color != color ||
        oldDelegate.theme.colorScheme.error != theme.colorScheme.error;
  }
}
