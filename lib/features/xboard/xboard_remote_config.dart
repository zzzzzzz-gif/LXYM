import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tried in order until one answers. Keep several on different domains and
/// hosts, so the app can still find the panel when one domain is blocked.
const xboardBootstrapUrls = <String>[
  'https://ht.zhslink.com/api/v1/lanxing/config',
];

const _cacheKey = 'xboard_remote_config';

class XboardRemoteConfig {
  const XboardRemoteConfig({
    this.apiDomains = const [],
    this.siteName = '',
    this.themeColor,
    this.homeText = '',
    this.noticeEnabled = false,
    this.noticePopup = false,
    this.noticeTitle = '',
    this.noticeContent = '',
    this.noticeId = '',
    this.registerEnabled = true,
    this.registerUrl = '',
    this.forgotUrl = '',
    this.supportUrl = '',
    this.tutorialUrl = '',
    this.websiteUrl = '',
    this.latestVersion = '',
    this.minVersion = '',
    this.updateNote = '',
    this.downloadUrls = const {},
  });

  final List<String> apiDomains;
  final String siteName;
  final Color? themeColor;
  final String homeText;
  final bool noticeEnabled;
  final bool noticePopup;
  final String noticeTitle;
  final String noticeContent;
  final String noticeId;
  final bool registerEnabled;
  final String registerUrl;
  final String forgotUrl;
  final String supportUrl;
  final String tutorialUrl;
  final String websiteUrl;
  final String latestVersion;
  final String minVersion;
  final String updateNote;

  /// Keys: android, windows, mac, ios.
  final Map<String, String> downloadUrls;

  factory XboardRemoteConfig.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> section(String key) {
      final value = json[key];
      return value is Map<String, dynamic> ? value : const {};
    }

    String str(Map<String, dynamic> map, String key) {
      final value = map[key];
      return value is String ? value.trim() : '';
    }

    final notice = section('notice');
    final register = section('register');
    final links = section('links');
    final update = section('update');
    final domains = json['api_domains'];
    final color = str(json, 'theme_color');
    Color? parsedColor;
    if (RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)) {
      parsedColor = Color(int.parse('FF${color.substring(1)}', radix: 16));
    }
    return XboardRemoteConfig(
      apiDomains: domains is List
          ? [
              for (final item in domains)
                if (item is String && item.startsWith('http'))
                  item.replaceAll(RegExp(r'/+$'), ''),
            ]
          : const [],
      siteName: str(json, 'site_name'),
      themeColor: parsedColor,
      homeText: str(json, 'home_text'),
      noticeEnabled: notice['enabled'] == true,
      noticePopup: notice['popup'] == true,
      noticeTitle: str(notice, 'title'),
      noticeContent: str(notice, 'content'),
      noticeId: str(notice, 'id'),
      registerEnabled: register['enabled'] != false,
      registerUrl: str(register, 'url'),
      forgotUrl: str(register, 'forgot_url'),
      supportUrl: str(links, 'support'),
      tutorialUrl: str(links, 'tutorial'),
      websiteUrl: str(links, 'website'),
      latestVersion: str(update, 'latest_version'),
      minVersion: str(update, 'min_version'),
      updateNote: str(update, 'note'),
      downloadUrls: {
        'android': str(update, 'android_url'),
        'windows': str(update, 'windows_url'),
        'mac': str(update, 'mac_url'),
        'ios': str(update, 'ios_url'),
      },
    );
  }
}

/// Compares dotted versions such as 1.2.10 and 1.2.9; returns <0, 0 or >0.
int compareXboardVersion(String a, String b) {
  List<int> parts(String v) =>
      v.split(RegExp(r'[.+-]')).map((p) => int.tryParse(p) ?? 0).toList();
  final pa = parts(a);
  final pb = parts(b);
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x - y;
  }
  return 0;
}

class XboardRemoteConfigStore {
  XboardRemoteConfigStore._();

  static final instance = XboardRemoteConfigStore._();

  final config = ValueNotifier<XboardRemoteConfig>(const XboardRemoteConfig());

  /// The panel address requests go to; the first domain that answered.
  final apiBase = ValueNotifier<String>('');

  final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 8),
      validateStatus: (_) => true,
    ),
  );

  Future<void>? _loading;

  /// Restores the cached copy at once, then refreshes from the network.
  Future<void> load() => _loading ??= _load().whenComplete(() => _loading = null);

  Future<void> _load() async {
    final cached = await _readCache();
    if (cached != null) {
      config.value = cached;
      await _pickApiBase(cached.apiDomains);
    }
    final fresh = await _fetch(cached);
    if (fresh != null) {
      config.value = fresh;
      await _pickApiBase(fresh.apiDomains);
    }
    if (apiBase.value.isEmpty) {
      apiBase.value = _fallbackBase();
    }
  }

  String _fallbackBase() {
    final uri = Uri.parse(xboardBootstrapUrls.first);
    return '${uri.scheme}://${uri.authority}';
  }

  Future<XboardRemoteConfig?> _fetch(XboardRemoteConfig? cached) async {
    final urls = <String>[
      for (final domain in cached?.apiDomains ?? const <String>[])
        '$domain/api/v1/lanxing/config',
      ...xboardBootstrapUrls,
    ];
    for (final url in urls.toSet()) {
      try {
        final response = await _dio.get<dynamic>(url);
        var body = response.data;
        if (body is String) body = jsonDecode(body);
        if (response.statusCode == 200 &&
            body is Map<String, dynamic> &&
            body['data'] is Map<String, dynamic>) {
          final data = body['data'] as Map<String, dynamic>;
          await _writeCache(data);
          return XboardRemoteConfig.fromJson(data);
        }
      } catch (_) {}
    }
    return null;
  }

  Future<void> _pickApiBase(List<String> domains) async {
    if (domains.isEmpty) return;
    for (final domain in domains) {
      try {
        final response = await _dio.get<dynamic>(
          '$domain/api/v1/guest/comm/config',
        );
        if (response.statusCode == 200) {
          apiBase.value = domain;
          return;
        }
      } catch (_) {}
    }
    if (apiBase.value.isEmpty) apiBase.value = domains.first;
  }

  Future<XboardRemoteConfig?> _readCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return null;
      final json = jsonDecode(raw);
      return json is Map<String, dynamic>
          ? XboardRemoteConfig.fromJson(json)
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(data));
    } catch (_) {}
  }
}

final xboardRemoteConfig = XboardRemoteConfigStore.instance;
