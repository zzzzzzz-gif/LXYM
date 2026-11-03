import 'dart:async';

import 'package:fl_clash/features/xboard/xboard_api.dart';
import 'package:fl_clash/features/xboard/xboard_plans_page.dart';
import 'package:fl_clash/features/xboard/xboard_session.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/tools.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

String formatXboardBytes(int bytes) {
  const gb = 1024 * 1024 * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
  const mb = 1024 * 1024;
  return '${(bytes / mb).toStringAsFixed(1)} MB';
}

String formatXboardDate(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}

void showXboardMessage(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));
}

class XboardAccountView extends ConsumerStatefulWidget {
  const XboardAccountView({super.key});

  @override
  ConsumerState<XboardAccountView> createState() => _XboardAccountViewState();
}

class _XboardAccountViewState extends ConsumerState<XboardAccountView> {
  XboardSubscribe? _subscribe;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool syncProfile = false}) async {
    final auth = xboardAuth;
    if (auth == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final subscribe = await xboardApi.getSubscribe(auth);
      if (!mounted) return;
      setState(() => _subscribe = subscribe);
      if (syncProfile) {
        await syncXboardProfile(
          ref,
          subscribe.subscribeUrl,
          forceUpdate: true,
        );
      }
    } on XboardException catch (e) {
      if (e.unauthorized) {
        if (mounted) await clearXboardSession(ref);
        return;
      }
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openPlans() async {
    final bought = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const XboardPlansPage()),
    );
    if (bought == true) await _load();
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ToolsView()),
    );
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出后会断开连接并删除本机的订阅，确定退出吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await clearXboardSession(ref);
  }

  Widget _buildInfoCard(BuildContext context) {
    final theme = Theme.of(context);
    final subscribe = _subscribe;
    if (subscribe == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: _error != null
              ? Text(_error!, style: TextStyle(color: theme.colorScheme.error))
              : const CircularProgressIndicator(),
        ),
      );
    }
    final expiredAt = subscribe.expiredAt;
    final total = subscribe.total;
    final progress = total > 0
        ? (subscribe.used / total).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final remaining = total - subscribe.used;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subscribe.email, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Text(
              subscribe.planName ?? '暂未订阅套餐',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              subscribe.planName == null
                  ? '购买套餐后即可使用'
                  : expiredAt == null
                  ? '长期有效'
                  : '到期时间：${formatXboardDate(expiredAt)}',
              style: theme.textTheme.bodyMedium,
            ),
            if (total > 0) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 8),
              Text(
                '已用 ${formatXboardBytes(subscribe.used)} / '
                '${formatXboardBytes(total)}，'
                '剩余 ${formatXboardBytes(remaining > 0 ? remaining : 0)}',
                style: theme.textTheme.bodySmall,
              ),
              if (subscribe.resetDay != null)
                Text(
                  '${subscribe.resetDay} 天后重置流量',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      _buildInfoCard(context),
      if (_error != null && _subscribe != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      generateSection(
        items: [
          ListItem(
            leading: const GlyphIcon(AppGlyphs.star),
            title: Text(_subscribe?.planName == null ? '购买套餐' : '续费 / 更换套餐'),
            onTap: _openPlans,
          ),
          ListItem(
            leading: const GlyphIcon(AppGlyphs.refresh),
            title: const Text('刷新账号与订阅'),
            onTap: _loading ? null : () => _load(syncProfile: true),
          ),
          ListItem(
            leading: const GlyphIcon(AppGlyphs.account),
            title: const Text('退出登录'),
            onTap: _logout,
          ),
          ListItem(
            leading: const GlyphIcon(AppGlyphs.settings),
            title: const Text('设置'),
            onTap: _openSettings,
          ),
        ],
      ),
    ];
    return CommonScaffold(
      title: '我的',
      isLoading: _loading,
      body: RefreshIndicator(
        onRefresh: () => _load(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: 20 + context.bottomInset,
          ),
          children: items,
        ),
      ),
    );
  }
}
