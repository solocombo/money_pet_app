import 'dart:math';

import 'package:flutter/material.dart';

/// 簡單的自繪圖表，不另外引入圖表套件。

class ChartSegment {
  const ChartSegment(this.label, this.value, this.color);
  final String label;
  final double value;
  final Color color;
}

/// 圓環圖。中間可以放文字。
class DonutChart extends StatelessWidget {
  const DonutChart({super.key, required this.segments, this.center, this.size = 160});
  final List<ChartSegment> segments;
  final Widget? center;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _DonutPainter(segments, Theme.of(context).colorScheme.surfaceContainerHighest),
          child: Center(child: center),
        ),
      );
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.segments, this.empty);
  final List<ChartSegment> segments;
  final Color empty;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.16;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final total = segments.fold<double>(0, (s, e) => s + e.value);
    if (total <= 0) {
      canvas.drawArc(rect, 0, 2 * pi, false, paint..color = empty);
      return;
    }
    // 每段之間留一點空隙（只有一段時不留）
    final gap = segments.length > 1 ? 0.02 : 0.0;
    var start = -pi / 2;
    for (final s in segments) {
      final sweep = s.value / total * 2 * pi;
      if (sweep > gap) {
        canvas.drawArc(rect, start + gap / 2, sweep - gap, false, paint..color = s.color);
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.segments != segments;
}

/// 每組兩根柱子（例如支出 / 收入）的長條圖。
class PairedBarChart extends StatelessWidget {
  const PairedBarChart({
    super.key,
    required this.labels,
    required this.a,
    required this.b,
    required this.colorA,
    required this.colorB,
    this.height = 160,
    this.highlightLast = true,
  });

  final List<String> labels;
  final List<double> a;
  final List<double> b;
  final Color colorA;
  final Color colorB;
  final double height;
  final bool highlightLast;

  @override
  Widget build(BuildContext context) {
    final maxV = [...a, ...b, 1.0].reduce(max);
    final t = Theme.of(context).textTheme.labelSmall;
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Opacity(
                opacity: highlightLast && i != labels.length - 1 ? 0.55 : 1,
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _bar(a[i] / maxV, colorA),
                        const SizedBox(width: 3),
                        _bar(b[i] / maxV, colorB),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(labels[i], style: t),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bar(double ratio, Color c) => LayoutBuilder(
        builder: (_, box) => Container(
          width: 10,
          height: max(2, box.maxHeight * ratio.clamp(0, 1)),
          decoration: BoxDecoration(color: c, borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
        ),
      );
}

/// 折線圖（資產趨勢）。
class LineChart extends StatelessWidget {
  const LineChart({super.key, required this.values, required this.color, this.height = 120});
  final List<double> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _LinePainter(values, color)),
      );
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    var lo = values.reduce(min);
    var hi = values.reduce(max);
    if (hi == lo) {
      hi += 1;
      lo -= 1;
    }
    Offset pt(int i) {
      final x = values.length == 1 ? size.width / 2 : size.width * i / (values.length - 1);
      final y = size.height - (values[i] - lo) / (hi - lo) * (size.height - 8) - 4;
      return Offset(x, y);
    }

    final path = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(pt(i).dx, pt(i).dy);
    }
    final fill = Path.from(path)
      ..lineTo(pt(values.length - 1).dx, size.height)
      ..lineTo(pt(0).dx, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round);
    canvas.drawCircle(pt(values.length - 1), 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.values != values;
}

/// 主類別的固定配色。
const List<Color> groupPalette = [
  Color(0xFFFF9F43), // 飲食
  Color(0xFFEE5253), // 健康
  Color(0xFF54A0FF), // 生活
  Color(0xFFF368E0), // 娛樂
  Color(0xFF5F27CD), // 學習
  Color(0xFF10AC84), // 交通
  Color(0xFF8395A7), // 其他
];
