import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

const String kRevenueCatAndroidApiKey = 'goog_BciSaSAifHmoslXIAxphkDBxLUT';
// Clé « appl_… » de l'app iOS dans RevenueCat (à créer avec le compte
// Apple Developer). Vide → Premium indisponible sur iPhone, sans erreur.
const String kRevenueCatIosApiKey = '';
const String kPremiumEntitlementId = 'zamu_premium';

class RevenueCatService extends GetxService {
  final RxBool isPremium = false.obs;
  final Rx<Offerings?> offerings = Rx<Offerings?>(null);
  final RxBool isProcessing = false.obs;

  Future<RevenueCatService> init() async {
    final cle = Platform.isIOS ? kRevenueCatIosApiKey : kRevenueCatAndroidApiKey;
    if (cle.isEmpty) {
      debugPrint('RevenueCat : pas de clé pour cette plateforme');
      return this;
    }
    await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.error);
    final configuration = PurchasesConfiguration(cle);
    await Purchases.configure(configuration);
    Purchases.addCustomerInfoUpdateListener(_onCustomerInfoUpdate);
    final customerInfo = await Purchases.getCustomerInfo();
    _updatePremiumStatus(customerInfo);
    await fetchOfferings();
    return this;
  }

  Future<void> loginRevenueCat(String supabaseUserId) async {
    try {
      await Purchases.logIn(supabaseUserId);
      final customerInfo = await Purchases.getCustomerInfo();
      _updatePremiumStatus(customerInfo);
    } catch (e) {
      debugPrint('RevenueCat login error: $e');
    }
  }

  Future<void> logoutRevenueCat() async {
    try {
      await Purchases.logOut();
      isPremium.value = false;
    } catch (e) {
      debugPrint('RevenueCat logout error: $e');
    }
  }

  Future<void> fetchOfferings() async {
    try {
      offerings.value = await Purchases.getOfferings();
    } catch (e) {
      debugPrint('RevenueCat fetchOfferings error: $e');
    }
  }

  Future<bool> purchasePackage(Package package) async {
    isProcessing.value = true;
    try {
      final result = await Purchases.purchasePackage(package);
      _updatePremiumStatus(result.customerInfo);
      return isPremium.value;
    } on PlatformException catch (e) {
      final errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode != PurchasesErrorCode.purchaseCancelledError) {
        debugPrint('RevenueCat purchase error: $errorCode');
      }
      return false;
    } finally {
      isProcessing.value = false;
    }
  }

  Future<bool> restorePurchases() async {
    isProcessing.value = true;
    try {
      final customerInfo = await Purchases.restorePurchases();
      _updatePremiumStatus(customerInfo);
      return isPremium.value;
    } catch (e) {
      debugPrint('RevenueCat restore error: $e');
      return false;
    } finally {
      isProcessing.value = false;
    }
  }

  void _onCustomerInfoUpdate(CustomerInfo customerInfo) =>
      _updatePremiumStatus(customerInfo);

  void _updatePremiumStatus(CustomerInfo customerInfo) {
    final entitlement = customerInfo.entitlements.all[kPremiumEntitlementId];
    isPremium.value = entitlement?.isActive ?? false;
  }
}
