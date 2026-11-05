import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models.dart';
import '../../domain/date_utils.dart';
import '../../domain/evolution_diary.dart';
import '../../domain/finance_rules.dart';
import '../../services/report_service.dart';
import '../../state/providers.dart';

/// 顯示分享卡預覽，按下分享後輸出 PNG。
/// 為了隱私，卡片上**不放支出金額**，只放寵物、記帳天數與省下的錢。
Future<void> showShareCard(BuildContext context, WidgetRef ref, Pet pet) async {
  final s = ref.read(servicesProvider);
  final now = s.ctx.now();
  final report = await ReportService(s.ctx).monthReport(monthKey(now));
  final streak = await s.tasks.currentStreak();
  if (!context.mounted) return;
  final key = GlobalKey();
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      contentPadding: const EdgeInsets.all(12),
      content: SingleChildScrollView(
        child: RepaintBoundary(
          key: key,
          child: _Card(
            pet: pet,
            days: daysBetween(pet.createdAt, now) + 1,
            streak: streak,
            recordedDays: report.recordedDays,
            saved: report.saved,
            noSpendDays: report.noSpendDays,
            month: now.month,
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
        FilledButton.icon(
          icon: const Icon(Icons.share),
          label: const Text('分享'),
          onPressed: () async {
            try {
              final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
              final image = await boundary.toImage(pixelRatio: 3);
              final data = await image.toByteData(format: ui.ImageByteFormat.png);
              await SharePlus.instance.share(ShareParams(
                files: [XFile.fromData(data!.buffer.asUint8List(), mimeType: 'image/png', name: 'money_pet.png')],
                text: '我在「錢寵」養了 ${pet.name}，一起記帳省錢吧！',
              ));
            } catch (e) {
              if (c.mounted) toast(c, '分享失敗：$e');
            }
          },
        ),
      ],
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({
    required this.pet,
    required this.days,
    required this.streak,
    required this.recordedDays,
    required this.saved,
    required this.noSpendDays,
    required this.month,
  });

  final Pet pet;
  final int days;
  final int streak;
  final int recordedDays;
  final int saved;
  final int noSpendDays;
  final int month;

  @override
  Widget build(BuildContext context) {
    final form = pet.isEvolved ? evolvedForms[pet.type] : null;
    return Container(
      width: 300,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFE3C2), Color(0xFFFFB86B)],
        ),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(form?.emoji ?? pet.type.emoji, style: const TextStyle(fontSize: 88)),
        Text(pet.name,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF5A3410))),
        if (form != null)
          Text('✨ ${form.title}', style: const TextStyle(color: Color(0xFF8A5A00), fontWeight: FontWeight.w600)),
        Text('我們一起生活了 $days 天 · 智慧 Lv${pet.stats.wisdomLevel}',
            style: const TextStyle(color: Color(0xFF7A4A1E))),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(children: [
            Text('$month 月成績', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5A3410))),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _Stat('🔥', '$streak 天', '連續記帳'),
              _Stat('📒', '$recordedDays 天', '有記帳'),
              _Stat('🌱', '$noSpendDays 天', '零支出'),
            ]),
            if (saved > 0) ...[
              const SizedBox(height: 8),
              Text('💰 回饋折扣共省下 ${formatMoney(saved)}',
                  style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
        const SizedBox(height: 14),
        const Text('錢寵｜記帳養寵物，省錢換獎勵',
            style: TextStyle(fontSize: 12, color: Color(0xFF7A4A1E))),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.emoji, this.value, this.label);
  final String emoji;
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Column(children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5A3410))),
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF7A4A1E))),
      ]);
}
