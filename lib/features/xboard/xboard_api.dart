import 'dart:convert';

import 'package:dio/dio.dart';

const xboardBaseUrl = 'https://ht.zhslink.com';
const xboardProfileLabel = '蓝星Cloud';

class XboardException implements Exception {
  const XboardException(this.message);

  final String message;

  @override
  String toString() => message;
}

class XboardSubscribe {
  const XboardSubscribe({
    required this.subscribeUrl,
    required this.planName,
    required this.expiredAt,
    required this.used,
    required this.total,
  });

  final String subscribeUrl;
  final String? planName;
  final DateTime? expiredAt;
  final int used;
  final int total;
}

class XboardApi {
  XboardApi()
    : _dio = Dio(
        BaseOptions(
          baseUrl: xboardBaseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          validateStatus: (_) => true,
        ),
      );

  final Dio _dio;

  Map<String, dynamic> _unwrap(Response<dynamic> response) {
    var body = response.data;
    if (body is String) {
      try {
        body = jsonDecode(body);
      } catch (_) {
        throw const XboardException('服务器返回异常，请稍后再试');
      }
    }
    if (body is! Map<String, dynamic>) {
      throw const XboardException('服务器返回异常，请稍后再试');
    }
    final status = response.statusCode ?? 0;
    if (status == 401 || status == 403) {
      throw const XboardException('登录已失效，请重新登录');
    }
    if (status < 200 || status >= 300 || body['status'] == 'fail') {
      final message = body['message'];
      throw XboardException(
        message is String && message.isNotEmpty ? message : '请求失败（$status）',
      );
    }
    final data = body['data'];
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

  Future<String> login(String email, String password) => _guard(() async {
    final response = await _dio.post<dynamic>(
      '/api/v1/passport/auth/login',
      data: {'email': email, 'password': password},
    );
    final authData = _unwrap(response)['auth_data'];
    if (authData is! String || authData.isEmpty) {
      throw const XboardException('登录失败，请稍后再试');
    }
    return authData;
  });

  Future<XboardSubscribe> getSubscribe(String authData) => _guard(() async {
    final response = await _dio.get<dynamic>(
      '/api/v1/user/getSubscribe',
      options: Options(headers: {'Authorization': authData}),
    );
    final data = _unwrap(response);
    final url = data['subscribe_url'];
    if (url is! String || url.isEmpty) {
      throw const XboardException('当前账号没有可用订阅，请先购买套餐');
    }
    final plan = data['plan'];
    final expiredAt = data['expired_at'];
    int asInt(Object? value) => value is num ? value.toInt() : 0;
    return XboardSubscribe(
      subscribeUrl: url,
      planName: plan is Map ? plan['name'] as String? : null,
      expiredAt: expiredAt is num && expiredAt > 0
          ? DateTime.fromMillisecondsSinceEpoch(expiredAt.toInt() * 1000)
          : null,
      used: asInt(data['u']) + asInt(data['d']),
      total: asInt(data['transfer_enable']),
    );
  });
}
