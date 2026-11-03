import 'dart:async';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/xboard/xboard_account_view.dart';
import 'package:fl_clash/features/xboard/xboard_api.dart';
import 'package:fl_clash/features/xboard/xboard_session.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

String _formatPrice(int cents) {
  final yuan = cents / 100;
  return yuan == yuan.roundToDouble()
      ? '¥${yuan.toStringAsFixed(0)}'
      : '¥${yuan.toStringAsFixed(2)}';
}

class XboardPlansPage extends ConsumerStatefulWidget {
  const XboardPlansPage({super.key, this.embedded = false});

  /// 作为底部标签页嵌入时为 true：不 pop，不显示返回按钮。
  final bool embedded;

  @override
  ConsumerState<XboardPlansPage> createState() => _XboardPlansPageState();
}

class _XboardPlansPageState extends ConsumerState<XboardPlansPage> {
  List<XboardPlan>? _plans;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final auth = xboardAuth;
    if (auth == null) return;
    setState(() => _error = null);
    try {
      final plans = await xboardApi.fetchPlans(auth);
      if (mounted) setState(() => _plans = plans);
    } on XboardException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<bool> _confirm(String title, String content, String ok) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(ok),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<XboardPaymentMethod?> _pickMethod(
    List<XboardPaymentMethod> methods,
  ) async {
    if (methods.length == 1) return methods.first;
    return showDialog<XboardPaymentMethod>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择支付方式'),
        children: [
          for (final method in methods)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(method),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(method.name),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _buy(XboardPlan plan, String period) async {
    final auth = xboardAuth;
    if (auth == null || _busy) return;
    final price = plan.prices[period] ?? 0;
    final periodName = xboardPeriods[period] ?? period;
    final confirmed = await _confirm(
      '确认购买',
      '${plan.name}（$periodName）\n价格：${_formatPrice(price)}',
      '去支付',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      final pending = await xboardApi.fetchPendingOrders(auth);
      if (pending.isNotEmpty) {
        if (!mounted) return;
        final cancel = await _confirm(
          '有未支付的订单',
          '需要先取消之前未支付的订单才能下新订单，是否取消？',
          '取消旧订单',
        );
        if (!cancel) return;
        for (final tradeNo in pending) {
          await xboardApi.cancelOrder(auth, tradeNo);
        }
      }
      final methods = await xboardApi.fetchPaymentMethods(auth);
      if (methods.isEmpty) {
        throw const XboardException('暂无可用的支付方式，请联系客服');
      }
      final tradeNo = await xboardApi.createOrder(
        auth,
        planId: plan.id,
        period: period,
      );
      if (!mounted) return;
      final method = await _pickMethod(methods);
      if (method == null) {
        await xboardApi.cancelOrder(auth, tradeNo);
        return;
      }
      final checkout = await xboardApi.checkout(
        auth,
        tradeNo: tradeNo,
        methodId: method.id,
      );
      if (checkout.type == -1) {
        await _onPaid();
        return;
      }
      final target = checkout.data?.toString() ?? '';
      final uri = Uri.tryParse(target);
      if (uri == null || !uri.hasScheme) {
        throw const XboardException('支付链接无效，请联系客服');
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!mounted) return;
      await _waitForPayment(auth, tradeNo);
    } on XboardException catch (e) {
      if (mounted) showXboardMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _waitForPayment(String auth, String tradeNo) async {
    while (mounted) {
      final action = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('等待支付'),
          content: const Text('已打开支付页面，付款完成后请回到这里点击“我已完成支付”。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('cancel'),
              child: const Text('取消订单'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('check'),
              child: const Text('我已完成支付'),
            ),
          ],
        ),
      );
      if (action == 'cancel') {
        await xboardApi.cancelOrder(auth, tradeNo);
        if (mounted) showXboardMessage(context, '订单已取消');
        return;
      }
      final status = await xboardApi.checkOrder(auth, tradeNo);
      if (status == 3 || status == 4) {
        await _onPaid();
        return;
      }
      if (status == 1) {
        if (!mounted) return;
        if (widget.embedded) {
          showXboardMessage(context, '支付成功，套餐开通中，请稍后刷新查看');
          await _load();
          _goToAccount();
        } else {
          showXboardMessage(context, '支付成功，套餐开通中，请稍后在“我的”页面刷新');
          Navigator.of(context).pop(true);
        }
        return;
      }
      if (status == 2) {
        if (mounted) showXboardMessage(context, '订单已取消或已过期');
        return;
      }
      if (mounted) showXboardMessage(context, '还没有收到付款，请完成支付后再试');
    }
  }

  Future<void> _onPaid() async {
    final auth = xboardAuth;
    if (auth != null) {
      final subscribe = await xboardApi.getSubscribe(auth);
      if (mounted) {
        await syncXboardProfile(
          ref,
          subscribe.subscribeUrl,
          forceUpdate: true,
        );
      }
    }
    if (!mounted) return;
    showXboardMessage(context, '购买成功，订阅已更新');
    if (widget.embedded) {
      await _load();
      _goToAccount();
    } else {
      Navigator.of(context).pop(true);
    }
  }

  void _goToAccount() {
    ref.read(currentPageLabelProvider.notifier).toPage(PageLabel.account);
  }

  Widget _buildPlan(BuildContext context, XboardPlan plan) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(plan.name, style: theme.textTheme.titleLarge),
            if (plan.content.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(plan.content, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 12),
            if (plan.soldOut)
              Text('已售罄', style: TextStyle(color: theme.colorScheme.error))
            else if (plan.prices.isEmpty)
              const Text('暂无可购买的周期')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in plan.prices.entries)
                    OutlinedButton(
                      onPressed: _busy ? null : () => _buy(plan, entry.key),
                      child: Text(
                        '${xboardPeriods[entry.key] ?? entry.key} '
                        '${_formatPrice(entry.value)}',
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plans = _plans;
    Widget body;
    if (plans == null) {
      body = Center(
        child: _error != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  const SizedBox(height: 12),
                  TextButton(onPressed: _load, child: const Text('重试')),
                ],
              )
            : const CircularProgressIndicator(),
      );
    } else if (plans.isEmpty) {
      body = const Center(child: Text('暂无可购买的套餐'));
    } else {
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [for (final plan in plans) _buildPlan(context, plan)],
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('购买套餐'),
        automaticallyImplyLeading: !widget.embedded,
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: body,
    );
  }
}
