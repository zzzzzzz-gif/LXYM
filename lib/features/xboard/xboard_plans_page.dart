import 'dart:async';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/xboard/xboard_account_view.dart';
import 'package:fl_clash/features/xboard/xboard_api.dart';
import 'package:fl_clash/features/xboard/xboard_session.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

const _plansBrandColor = Color(0xFF2563EB);

String _formatPrice(int cents) {
  final yuan = cents / 100;
  return yuan == yuan.roundToDouble()
      ? '¥${yuan.toStringAsFixed(0)}'
      : '¥${yuan.toStringAsFixed(2)}';
}

/// 把套餐介绍（可能含 HTML）清洗成逐行卖点。
List<String> _cleanPlanLines(String raw) {
  if (raw.isEmpty) return const [];
  // 1. 源码里的换行与制表符先变空格。
  var s = raw.replaceAll(RegExp(r'[\r\n\t]'), ' ');
  // 2. 块级标签变换行。
  s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'</li\s*>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'</div\s*>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'</h[1-6]\s*>', caseSensitive: false), '\n');
  // 3. 去掉剩余标签，实体空格还原。
  s = s.replaceAll(RegExp(r'<[^>]*>'), '');
  s = s.replaceAll('&nbsp;', ' ');
  // 4. 逐行清理：合并连续空格、去首尾、删空行。
  return s
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((line) => line.isNotEmpty)
      .toList();
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
    final colorScheme = context.colorScheme;
    final dark = colorScheme.brightness == Brightness.dark;
    final cardColor = dark ? const Color(0xFF23252D) : Colors.white;
    final lines = _cleanPlanLines(plan.content);
    // 最便宜的周期用于高亮。
    String? cheapest;
    int? cheapestPrice;
    for (final entry in plan.prices.entries) {
      if (cheapestPrice == null || entry.value < cheapestPrice) {
        cheapestPrice = entry.value;
        cheapest = entry.key;
      }
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: ShapeDecoration(color: cardColor, shape: AppShape.all(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            plan.name,
            style: AppTextStyle.title3.of(context, emphasized: true),
          ),
          if (lines.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: GlyphIcon(
                        AppGlyphs.check,
                        size: 15,
                        color: _plansBrandColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        line,
                        style: AppTextStyle.footnote.of(context).copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 14),
          if (plan.soldOut)
            Text(
              '已售罄',
              style: AppTextStyle.subheadline.of(context).copyWith(
                color: colorScheme.error,
              ),
            )
          else if (plan.prices.isEmpty)
            Text(
              '暂无可购买的周期',
              style: AppTextStyle.footnote.of(context).copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in plan.prices.entries)
                  _PriceChip(
                    label:
                        '${xboardPeriods[entry.key] ?? entry.key} '
                        '${_formatPrice(entry.value)}',
                    highlighted: entry.key == cheapest,
                    enabled: !_busy,
                    onTap: () => _buy(plan, entry.key),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final dark = colorScheme.brightness == Brightness.dark;
    final pageColor = dark ? const Color(0xFF15171E) : const Color(0xFFF5F7FA);
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
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: 120 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [for (final plan in plans) _buildPlan(context, plan)],
      );
    }
    return Scaffold(
      backgroundColor: pageColor,
      appBar: AppBar(
        title: const Text('购买套餐'),
        backgroundColor: pageColor,
        elevation: 0,
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

/// 价格芯片：最便宜的周期高亮品牌蓝。
class _PriceChip extends StatelessWidget {
  const _PriceChip({
    required this.label,
    required this.highlighted,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool highlighted;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final dark = colorScheme.brightness == Brightness.dark;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: ShapeDecoration(
          color: highlighted
              ? _plansBrandColor
              : (dark
                    ? colorScheme.surfaceContainerHigh
                    : colorScheme.surfaceContainer),
          shape: AppShape.all(10),
          side: highlighted
              ? null
              : BorderSide(color: colorScheme.outlineVariant),
        ),
        child: Text(
          label,
          style: AppTextStyle.footnote.of(context).copyWith(
            color: highlighted
                ? const Color(0xFFFFFFFF)
                : colorScheme.onSurface,
            fontWeight: highlighted ? FontWeight.bold : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
