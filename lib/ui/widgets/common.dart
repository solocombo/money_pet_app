import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/enums.dart';
import '../../domain/pt_rules.dart';
import '../../state/providers.dart';

// ---------------------------------------------------------------------------
// San 值失控：亂碼文字
// ---------------------------------------------------------------------------

const _glyphs = '▓░▒¿҉ʬ⸮ᚦ⌇⍰ꙮ';

/// 把文字的一部分換成亂碼。用文字本身當種子，同一段文字每次結果一樣，不會閃爍。
String garble(String text, {double ratio = 0.4}) {
  if (text.isEmpty) return text;
  var seed = text.codeUnits.fold<int>(7, (h, c) => (h * 31 + c) & 0x7fffffff);
  final buf = StringBuffer();
  for (final rune in text.runes) {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    final ch = String.fromCharCode(rune);
    if (ch.trim().isNotEmpty && (seed % 100) / 100 < ratio) {
      buf.write(_glyphs[seed % _glyphs.length]);
    } else {
      buf.write(ch);
    }
  }
  return buf.toString();
}

/// 寵物失控時會變亂碼的文字。**只用在標題、寵物相關文字上**，
/// 不要用在金額、交易內容等記帳核心資訊（上架審查要求亂碼不影響核心功能）。
class GText extends ConsumerWidget {
  const GText(this.text, {super.key, this.style, this.textAlign});
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(garbleProvider);
    return Text(g ? garble(text) : text, style: style, textAlign: textAlign);
  }
}

/// 失控時把子元件輕微去飽和（變灰）。
class Desaturate extends StatelessWidget {
  const Desaturate({super.key, required this.enabled, required this.child});
  final bool enabled;
  final Widget child;

  static const double _s = 0.35; // 保留 35% 飽和度
  static const List<double> _matrix = [
    0.2126 + 0.7874 * _s, 0.7152 - 0.7152 * _s, 0.0722 - 0.0722 * _s, 0, 0,
    0.2126 - 0.2126 * _s, 0.7152 + 0.2848 * _s, 0.0722 - 0.0722 * _s, 0, 0,
    0.2126 - 0.2126 * _s, 0.7152 - 0.7152 * _s, 0.0722 + 0.9278 * _s, 0, 0,
    0, 0, 0, 1, 0,
  ];

  @override
  Widget build(BuildContext context) => enabled
      ? ColorFiltered(colorFilter: const ColorFilter.matrix(_matrix), child: child)
      : child;
}

// ---------------------------------------------------------------------------
// 顯示元件
// ---------------------------------------------------------------------------

Color attributeColor(PetAttribute a) => switch (a) {
      PetAttribute.fullness => Colors.orange,
      PetAttribute.health => Colors.red,
      PetAttribute.cleanliness => Colors.lightBlue,
      PetAttribute.mood => Colors.pink,
      PetAttribute.wisdom => Colors.indigo,
      PetAttribute.san => Colors.deepPurple,
    };

Color rarityColor(Rarity r) => switch (r) {
      Rarity.common => Colors.grey,
      Rarity.rare => Colors.blue,
      Rarity.epic => Colors.purple,
      Rarity.legendary => Colors.amber.shade700,
    };

class StatBar extends StatelessWidget {
  const StatBar({
    super.key,
    required this.attribute,
    required this.value,
    this.max = 100,
    this.trailing,
  });

  final PetAttribute attribute;
  final double value;
  final double max;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final color = attributeColor(attribute);
    final low = attribute != PetAttribute.wisdom && value < 30;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: GText(attribute.label,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: low ? Colors.red : null)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: max <= 0 ? 0 : (value / max).clamp(0, 1),
                minHeight: 10,
                color: color,
                backgroundColor: color.withValues(alpha: 0.15),
              ),
            ),
          ),
          SizedBox(
            width: 76,
            child: Text(
              trailing ?? value.round().toString(),
              textAlign: TextAlign.right,
              style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
        ],
      ),
    );
  }
}

class CoinChip extends ConsumerWidget {
  const CoinChip({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coins = ref.watch(coinsProvider).value ?? 0;
    final pt = ref.watch(ptProvider).value ?? 0;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('🪙 $coins'),
        const SizedBox(width: 10),
        Text('⭐ ${formatPt(pt)} PT'),
      ]),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Row(children: [
          Expanded(
            child: GText(text,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ),
          ?trailing,
        ]),
      );
}

class EmptyHint extends StatelessWidget {
  const EmptyHint(this.text, {super.key, this.icon = Icons.inbox_outlined});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(children: [
          Icon(icon, size: 40, color: Theme.of(context).disabledColor),
          const SizedBox(height: 8),
          Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).hintColor)),
        ]),
      );
}

/// AsyncValue 的通用顯示。
class AsyncView<T> extends StatelessWidget {
  const AsyncView(this.value, {super.key, required this.builder});
  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  @override
  Widget build(BuildContext context) => value.when(
        // 每次寫入後所有查詢都會重跑；保留舊資料避免整頁閃爍。
        skipLoadingOnReload: true,
        data: builder,
        loading: () => const Center(
            child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('發生錯誤：$e'))),
      );
}

// ---------------------------------------------------------------------------
// 輸入
// ---------------------------------------------------------------------------

final digitsOnly = [FilteringTextInputFormatter.digitsOnly];
final decimalOnly = [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,4}'))];

Future<bool> confirmDialog(BuildContext context,
    {required String title, String? message, String confirm = '確定', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: Colors.red) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// 單一欄位輸入對話框。
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String? label,
  String initial = '',
  bool numeric = false,
  bool decimal = false,
  String? hint,
}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        keyboardType: numeric || decimal
            ? TextInputType.numberWithOptions(decimal: decimal)
            : TextInputType.text,
        inputFormatters: decimal ? decimalOnly : (numeric ? digitsOnly : null),
        decoration: InputDecoration(labelText: label, hintText: hint),
        onSubmitted: (v) => Navigator.pop(c, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('確定')),
      ],
    ),
  );
}

int? parseIntOrNull(String? s) => s == null ? null : int.tryParse(s.trim());

ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFFFF9F43), brightness: b);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    cardTheme: const CardThemeData(margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6)),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
  );
}
