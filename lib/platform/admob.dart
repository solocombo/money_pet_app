import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/ad_reward_service.dart';

/// AdMob 激勵式廣告。
///
/// ⚠️ 目前用的是 Google 官方的**測試廣告 ID**。上架前要換成自己的：
///   1. 這裡的 [_androidUnitId] / [_iosUnitId]
///   2. android/app/src/main/AndroidManifest.xml 的 APPLICATION_ID
///   3. ios/Runner/Info.plist 的 GADApplicationIdentifier
class AdMobGateway implements RewardedAdGateway {
  static const _androidUnitId = 'ca-app-pub-3940256099942544/5224354917';
  static const _iosUnitId = 'ca-app-pub-3940256099942544/1712485313';

  var _ready = false;

  String get _unitId =>
      defaultTargetPlatform == TargetPlatform.iOS ? _iosUnitId : _androidUnitId;

  @override
  Future<void> init() async {
    if (_ready) return;
    await MobileAds.instance.initialize();
    _ready = true;
  }

  @override
  Future<bool> show() async {
    try {
      await init();
      final ad = await _load();
      if (ad == null) return false;
      final done = Completer<bool>();
      var earned = false;
      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (a) {
          a.dispose();
          if (!done.isCompleted) done.complete(earned);
        },
        onAdFailedToShowFullScreenContent: (a, _) {
          a.dispose();
          if (!done.isCompleted) done.complete(false);
        },
      );
      await ad.show(onUserEarnedReward: (_, _) => earned = true);
      return await done.future;
    } catch (_) {
      return false;
    }
  }

  Future<RewardedAd?> _load() {
    final c = Completer<RewardedAd?>();
    RewardedAd.load(
      adUnitId: _unitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: c.complete,
        onAdFailedToLoad: (_) => c.complete(null),
      ),
    );
    return c.future.timeout(const Duration(seconds: 15), onTimeout: () => null);
  }
}
