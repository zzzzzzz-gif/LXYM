import 'dart:convert';

import 'package:dio/dio.dart';

const xboardBaseUrl = 'https://ht.zhslink.com';
const xboardProfileLabel = '蓝星Cloud';

class XboardException implements Exception {
  const XboardException(this.message, {this.unauthorized = false});

  final String message;
  final bool unauthorized;

  @override
  String toString() => message;
}

class XboardSubscribe {
  const XboardSubscribe({
    required this.subscribeUrl,
    required this.email,
    required this.planName,
    required this.expiredAt,
    required this.used,
    required this.total,
    required this.resetDay,
  });

  final String subscribeUrl;
  final String email;
  final String? planName;
  final DateTime? expiredAt;
  final int used;
  final int total;
  final int? resetDay;
}

const xboardPeriods = <String, String>{
  'month_price': '月付',
  'quarter_price': '季付',
  'half_year_price': '半年付',
  'year_price': '年付',
  'two_year_price': '两年付',
  'three_year_price': '三年付',
  'onetime_price': '一次性',
  'reset_price': '流量重置包',
};

class XboardPlan {
  const XboardPlan({
    required this.id,
    required this.name,
    required this.content,
    required this.prices,
    required this.soldOut,
  });

  final int id;
  final String name;
  final String content;

  /// Period key to price in cents, in [xboardPeriods] order.
  final Map<String, int> prices;
  final bool soldOut;
}

class XboardPaymentMethod {
  const XboardPaymentMethod({required this.id, required this.name});

  final int id;
  final String name;
}

class XboardCheckout {
  const XboardCheckout({required this.type, required this.data});

  /// -1: paid without payment, 0: QR code content, 1: URL to open.
  final int type;
  final Object? data;
}

int _asInt(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return num.tryParse(value)?.toInt() ?? 0;
  return 0;
}

String _stripHtml(String value) {
  return value
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

class XboardApi {
  XboardApi()
    : _dio = Dio(
        BaseOptions(
          baseUrl: xboardBaseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          validateStatus: (_) => true,
        ),
      );

  final Dio _dio;

  Map<String, dynamic> _body(Response<dynamic> response) {
    var body = response.data;
    if (body is String) {
      try {
        body = jsonDecode(body);
      } catch (_) {
        body = null;
      }
    }
    final status = response.statusCode ?? 0;
    if (status == 401 || status == 403) {
      throw const XboardException('登录已失效，请重新登录', unauthorized: true);
    }
    if (body is! Map<String, dynamic>) {
      throw XboardException('服务器返回异常（$status），请稍后再试');
    }
    if (status < 200 || status >= 300 || body['status'] == 'fail') {
      final message = body['message'];
      throw XboardException(
        message is String && message.isNotEmpty ? message : '请求失败（$status）',
      );
    }
    return body;
  }

  Object? _data(Response<dynamic> response) => _body(response)['data'];

  Map<String, dynamic> _dataMap(Response<dynamic> response) {
    final data = _data(response);
    if (data is! Map<String, dynamic>) {
      throw const XboardException('服务器返回异常，请稍后再试');
    }
    return data;
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException {
      throw const XboardException('无法连接服务器，请检查网络');
    }
  }

  Options _auth(String authData) =>
      Options(headers: {'Authorization': authData});

  Future<String> login(String email, String password) => _guard(() async {
    final response = await _dio.post<dynamic>(
      '/api/v1/passport/auth/login',
      data: {'email': email, 'password': password},
    );
    final authData = _dataMap(response)['auth_data'];
    if (authData is! String || authData.isEmpty) {
      throw const XboardException('登录失败，请稍后再试');
    }
    return authData;
  });

  Future<XboardSubscribe> getSubscribe(String authData) => _guard(() async {
    final response = await _dio.get<dynamic>(
      '/api/v1/user/getSubscribe',
      options: _auth(authData),
    );
    final data = _dataMap(response);
    final url = data['subscribe_url'];
    if (url is! String || url.isEmpty) {
      throw const XboardException('获取订阅失败，请稍后再试');
    }
    final plan = data['plan'];
    final expiredAt = _asInt(data['expired_at']);
    final resetDay = data['reset_day'];
    final email = data['email'];
    return XboardSubscribe(
      subscribeUrl: url,
      email: email is String ? email : '',
      planName: plan is Map && plan['name'] is String
          ? plan['name'] as String
          : null,
      expiredAt: expiredAt > 0
          ? DateTime.fromMillisecondsSinceEpoch(expiredAt * 1000)
          : null,
      used: _asInt(data['u']) + _asInt(data['d']),
      total: _asInt(data['transfer_enable']),
      resetDay: resetDay is num ? resetDay.toInt() : null,
    );
  });

  Future<List<XboardPlan>> fetchPlans(String authData) => _guard(() async {
    final response = await _dio.get<dynamic>(
      '/api/v1/user/plan/fetch',
      options: _auth(authData),
    );
    final data = _data(response);
    if (data is! List) return const [];
    final plans = <XboardPlan>[];
    for (final item in data) {
      if (item is! Map) continue;
      final prices = <String, int>{};
      for (final period in xboardPeriods.keys) {
        final price = item[period];
        if (price is num) prices[period] = price.round();
      }
      final content = item['content'];
      plans.add(
        XboardPlan(
          id: _asInt(item['id']),
          name: item['name']?.toString() ?? '',
          content: content is String ? _stripHtml(content) : '',
          prices: prices,
          soldOut: item['capacity_limit'] is String,
        ),
      );
    }
    return plans;
  });

  Future<List<XboardPaymentMethod>> fetchPaymentMethods(String authData) =>
      _guard(() async {
        final response = await _dio.get<dynamic>(
          '/api/v1/user/order/getPaymentMethod',
          options: _auth(authData),
        );
        final data = _data(response);
        if (data is! List) return const [];
        return [
          for (final item in data)
            if (item is Map)
              XboardPaymentMethod(
                id: _asInt(item['id']),
                name: item['name']?.toString() ?? '',
              ),
        ];
      });

  Future<List<String>> fetchPendingOrders(String authData) => _guard(() async {
    final response = await _dio.get<dynamic>(
      '/api/v1/user/order/fetch',
      queryParameters: {'status': 0},
      options: _auth(authData),
    );
    final data = _data(response);
    if (data is! List) return const [];
    return [
      for (final item in data)
        if (item is Map && item['trade_no'] != null)
          item['trade_no'].toString(),
    ];
  });

  Future<void> cancelOrder(String authData, String tradeNo) => _guard(() async {
    final response = await _dio.post<dynamic>(
      '/api/v1/user/order/cancel',
      data: {'trade_no': tradeNo},
      options: _auth(authData),
    );
    _body(response);
  });

  Future<String> createOrder(
    String authData, {
    required int planId,
    required String period,
  }) => _guard(() async {
    final response = await _dio.post<dynamic>(
      '/api/v1/user/order/save',
      data: {'plan_id': planId, 'period': period},
      options: _auth(authData),
    );
    final tradeNo = _data(response);
    if (tradeNo == null || tradeNo.toString().isEmpty) {
      throw const XboardException('创建订单失败，请稍后再试');
    }
    return tradeNo.toString();
  });

  Future<XboardCheckout> checkout(
    String authData, {
    required String tradeNo,
    required int methodId,
  }) => _guard(() async {
    final response = await _dio.post<dynamic>(
      '/api/v1/user/order/checkout',
      data: {'trade_no': tradeNo, 'method': methodId},
      options: _auth(authData),
    );
    final body = _body(response);
    return XboardCheckout(type: _asInt(body['type']), data: body['data']);
  });

  /// 0 pending, 1 processing, 2 cancelled, 3 completed, 4 discounted.
  Future<int> checkOrder(String authData, String tradeNo) => _guard(() async {
    final response = await _dio.get<dynamic>(
      '/api/v1/user/order/check',
      queryParameters: {'trade_no': tradeNo},
      options: _auth(authData),
    );
    return _asInt(_data(response));
  });
}
