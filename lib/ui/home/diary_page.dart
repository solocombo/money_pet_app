import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/evolution_diary.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';

/// 智慧 Lv3 解鎖寵物日記。
const int diaryUnlockLevel = 3;

final _diaryProvider = FutureProvider<List<(String, DiaryEntry)>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(servicesProvider).pets.diary();
});

class DiaryPage extends ConsumerWidget {
  const DiaryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pet = ref.watch(petProvider).value;
    final level = pet?.stats.wisdomLevel ?? 1;
    return Scaffold(
      appBar: AppBar(title: GText('${pet?.name ?? '寵物'}的日記')),
      body: level < diaryUnlockLevel
          ? const EmptyHint(
              '寵物的智慧到 Lv$diaryUnlockLevel 就會開始讓你看日記。\n'
              '（牠其實每天都有寫，只是還不好意思給你看）\n\n'
              '記學習類的帳、使用智慧道具可以提升智慧。',
              icon: Icons.lock_outline)
          : AsyncView(ref.watch(_diaryProvider), builder: (list) {
              if (list.isEmpty) return const EmptyHint('明天就會有第一篇日記了', icon: Icons.menu_book_outlined);
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final (date, e) = list[i];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(e.mood.emoji, style: const TextStyle(fontSize: 26)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(formatDiaryDate(date), style: Theme.of(context).textTheme.labelMedium),
                            const SizedBox(height: 4),
                            // 失控時寫的日記本來就是怪的，不另外套亂碼。
                            Text(e.text, style: const TextStyle(height: 1.5)),
                          ]),
                        ),
                      ]),
                    ),
                  );
                },
              );
            }),
    );
  }
}
