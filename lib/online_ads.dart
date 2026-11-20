import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class OnlineAds extends ChangeNotifier with WidgetsBindingObserver {
  static final _unit = switch (Platform.operatingSystem) {
    'android' =>
      kDebugMode
          ? 'ca-app-pub-3940256099942544/6300978111'
          : const String.fromEnvironment('MOYI_ADMOB_ANDROID_BANNER_ID'),
    'ios' =>
      kDebugMode
          ? 'ca-app-pub-3940256099942544/2934735716'
          : const String.fromEnvironment('MOYI_ADMOB_IOS_BANNER_ID'),
    _ => '',
  };

  final _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  BannerAd? _candidate;
  BannerAd? get banner => _loaded ? _candidate : null;
  bool _loaded = false;
  bool _online = false;
  bool _closed = false;
  bool _requesting = false;
  bool _privacyRequired = false;
  bool get canShowPrivacyOptions => _online && _privacyRequired;
  Future<bool>? _permission;
  Future<InitializationStatus>? _sdk;

  void start() {
    if (_unit.isEmpty || _subscription != null) return;
    WidgetsBinding.instance.addObserver(this);
    _subscription = _connectivity.onConnectivityChanged.listen(
      _connectionChanged,
      onError: (Object _) =>
          _connectionChanged(const [ConnectivityResult.none]),
    );
    unawaited(_checkConnection());
  }

  Future<void> _checkConnection() async {
    try {
      _connectionChanged(await _connectivity.checkConnectivity());
    } on Exception {
      _connectionChanged(const [ConnectivityResult.none]);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_checkConnection());
  }

  void _connectionChanged(List<ConnectivityResult> types) {
    if (_closed) return;
    final online = types.any((type) => type != ConnectivityResult.none);
    if (_online != online) {
      _online = online;
      if (!online) _removeBanner();
      notifyListeners();
    }
    if (online) unawaited(_requestBanner());
  }

  Future<bool> _consentAllowsAds() async {
    if (kDebugMode) return true;
    final consent = ConsentInformation.instance;
    final update = Completer<bool>();
    consent.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () => update.complete(true),
      (_) => update.complete(false),
    );
    if (await update.future && !_closed && _online) {
      await ConsentForm.loadAndShowConsentFormIfRequired((_) {});
    }
    final status = await consent.getPrivacyOptionsRequirementStatus();
    _privacyRequired = status == PrivacyOptionsRequirementStatus.required;
    if (!_closed) notifyListeners();
    return consent.canRequestAds();
  }

  Future<void> _requestBanner() async {
    if (_closed || !_online || _requesting || _candidate != null) return;
    _requesting = true;
    try {
      final eligible = await (_permission ??= _consentAllowsAds());
      if (!eligible) _permission = null;
      if (_closed || !_online || !eligible) return;
      await (_sdk ??= MobileAds.instance.initialize());
      if (_closed || !_online) return;
      final ad = BannerAd(
        adUnitId: _unit,
        size: AdSize.banner,
        request: const AdRequest(nonPersonalizedAds: true),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (_closed || !_online || !identical(ad, _candidate)) return;
            _loaded = true;
            notifyListeners();
          },
          onAdFailedToLoad: (ad, error) {
            if (identical(ad, _candidate)) _removeBanner();
            debugPrint('Banner could not load (${error.code}).');
          },
        ),
      );
      _candidate = ad;
      await ad.load();
    } on Exception catch (error) {
      _removeBanner();
      _permission = null;
      _sdk = null;
      debugPrint('Ads unavailable: ${error.runtimeType}');
    } finally {
      _requesting = false;
    }
  }

  Future<void> showPrivacyOptions() async {
    if (!canShowPrivacyOptions) return;
    _removeBanner();
    notifyListeners();
    try {
      await ConsentForm.showPrivacyOptionsForm((_) {});
      _permission = ConsentInformation.instance.canRequestAds();
      await _requestBanner();
    } on Exception catch (error) {
      debugPrint('Ad privacy options unavailable: ${error.runtimeType}');
    }
  }

  void _removeBanner() {
    final previous = _candidate;
    _candidate = null;
    _loaded = false;
    if (previous != null) unawaited(previous.dispose());
  }

  @override
  void dispose() {
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    _removeBanner();
    super.dispose();
  }
}
