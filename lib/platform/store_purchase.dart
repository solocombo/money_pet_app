import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

import '../services/premium_service.dart';

/// in_app_purchase 轉接層（Google Play / App Store 一次性購買）。
///
/// 目前在本機驗證收據（買斷 NT$90，風險可接受）；之後若要防破解再加伺服器驗證。
class StorePurchaseGateway implements PurchaseGateway {
  StorePurchaseGateway() {
    _sub = _iap.purchaseStream.listen(_onUpdates, onError: (_) {});
  }

  final _iap = InAppPurchase.instance;
  late final StreamSubscription<List<PurchaseDetails>> _sub;
  Future<void> Function()? _cb;
  ProductDetails? _product;

  @override
  set onPurchased(Future<void> Function() cb) => _cb = cb;

  Future<void> _onUpdates(List<PurchaseDetails> list) async {
    for (final p in list) {
      if (p.productID == premiumProductId &&
          (p.status == PurchaseStatus.purchased || p.status == PurchaseStatus.restored)) {
        await _cb?.call();
      }
      if (p.pendingCompletePurchase) await _iap.completePurchase(p);
    }
  }

  Future<ProductDetails?> _load() async {
    if (_product != null) return _product;
    if (!await _iap.isAvailable()) return null;
    final r = await _iap.queryProductDetails({premiumProductId});
    _product = r.productDetails.isEmpty ? null : r.productDetails.first;
    return _product;
  }

  @override
  Future<bool> isAvailable() async {
    try {
      return await _load() != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> price() async {
    try {
      return (await _load())?.price;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> buy() async {
    final p = await _load();
    if (p == null) return false;
    return _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: p));
  }

  @override
  Future<void> restore() => _iap.restorePurchases();

  void dispose() => _sub.cancel();
}
