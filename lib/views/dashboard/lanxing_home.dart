import 'dart:async';
import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/dashboard/widgets/card.dart';
import 'package:fl_clash/views/proxies/proxies.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_new_shapes/material_new_shapes.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// 首页：大圆形连接开关 + 模式切换 + 当前节点卡片。
class LanxingHomeView extends ConsumerStatefulWidget {
  const LanxingHomeView({super.key});

  @override
  ConsumerState<LanxingHomeView> createState() => _LanxingHomeViewState();
}

class _LanxingHomeViewState extends ConsumerState<LanxingHomeView> {
  /// 点击开关后进入「连接中」的本地标记，直到 isStartProvider 变化或超时。
  bool _pending = false;
  Timer? _pendingTimer;

  @override
  void initState() {
    super.initState();
    // 监听连接状态变化，一旦变化就结束「连接中」。
    ref.listenManual(isStartProvider, (prev, next) {
      if (_pending) {
        _clearPending();
      }
    });
  }

  void _clearPending() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
    if (_pending) {
      setState(() => _pending = false);
    }
  }

  @override
  void dispose() {
    _pendingTimer?.cancel();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_pending) return;
    final isStart = ref.read(isStartProvider);
    setState(() => _pending = true);
    // 15 秒超时兜底。
    _pendingTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted) return;
      _clearPending();
      _showToast('连接失败，请重试');
    });
    ref.read(commonActionProvider.notifier).toggleRunning();
  }

  void _showToast(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final isStart = ref.watch(isStartProvider);
    // 三态：连接中（本地 _pending）> 已连接 > 未连接。
    final connecting = _pending;
    final connected = !connecting && isStart;
    return Scaffold(
      backgroundColor: SurfaceLevel.page.colorOf(colorScheme),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TopBar(onService: () => _openPlaceholder('客服')),
              const SizedBox(height: 28),
              _ConnectButton(
                connecting: connecting,
                connected: connected,
                onTap: _toggle,
              ),
              const SizedBox(height: 32),
              _SectionTitle('选项'),
              const SizedBox(height: 10),
              _ModeSelector(),
              const SizedBox(height: 24),
              _SectionTitle('节点'),
              const SizedBox(height: 10),
              _NodeCard(onTap: () => _goToProxies()),
            ],
          ),
        ),
      ),
    );
  }

  void _goToProxies() {
    // 节点列表页（ProxiesView）作为次级页面 push 进入。
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProxiesView()),
    );
  }

  void _openPlaceholder(String name) {
    // 占位链接：后续接入真实客服地址。
    final uri = Uri.tryParse('https://example.com');
    if (uri != null) {
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

/// 顶部栏：App 图标 + 「蓝星Cloud」 + 右侧「客服」。
class _TopBar extends StatelessWidget {
  const _TopBar({required this.onService});

  final VoidCallback onService;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset(
            'assets/images/icon.png',
            width: 36,
            height: 36,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '蓝星Cloud',
          style: AppTextStyle.title2.of(context, emphasized: true),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: onService,
          icon: const GlyphIcon(AppGlyphs.account, size: 18),
          label: const Text('客服'),
        ),
      ],
    );
  }
}

/// 大圆形连接开关（复用 cookie-9 波浪形）。
class _ConnectButton extends StatelessWidget {
  const _ConnectButton({
    required this.connecting,
    required this.connected,
    required this.onTap,
  });

  final bool connecting;
  final bool connected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final size = MediaQuery.sizeOf(context).width * 0.45;
    final label = connecting
        ? '连接中'
        : connected
        ? '已连接'
        : '未连接';
    return Column(
      children: [
        _BreathingBadge(
          size: size,
          connecting: connecting,
          connected: connected,
          onTap: onTap,
        ),
        const SizedBox(height: 18),
        Text(
          label,
          style: AppTextStyle.title3.of(context, emphasized: true).copyWith(
            color: connecting || connected
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 带呼吸光晕的波浪圆按钮。
class _BreathingBadge extends StatefulWidget {
  const _BreathingBadge({
    required this.size,
    required this.connecting,
    required this.connected,
    required this.onTap,
  });

  final double size;
  final bool connecting;
  final bool connected;
  final VoidCallback onTap;

  @override
  State<_BreathingBadge> createState() => _BreathingBadgeState();
}

class _BreathingBadgeState extends State<_BreathingBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  @override
  void initState() {
    super.initState();
    _breath.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _breath.reverse();
      } else if (status == AnimationStatus.dismissed) {
        _breath.forward();
      }
    });
    _updateAnimation();
  }

  @override
  void didUpdateWidget(_BreathingBadge oldWidget) {
    super.didUpdateWidget();
    if (oldWidget.connected != widget.connected ||
        oldWidget.connecting != widget.connecting) {
      _updateAnimation();
    }
  }

  void _updateAnimation() {
    if (widget.connecting) {
      _breath.stop();
      _spin.repeat();
    } else if (widget.connected) {
      _spin.stop();
      _spin.value = 0;
      _breath.forward(from: 0);
    } else {
      _breath.stop();
      _spin.stop();
      _spin.value = 0;
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final brand = const Color(0xFF2563EB);
    final fill = widget.connected || widget.connecting
        ? brand
        : colorScheme.surfaceContainerHighest;
    return AnimatedBuilder(
      animation: Listenable.merge([_breath, _spin]),
      builder: (context, child) {
        final breath = _breath.value;
        final glow = widget.connected
            ? 0.25 + 0.2 * breath
            : widget.connecting
            ? 0.3
            : 0.0;
        return GestureDetector(
          onTap: widget.onTap,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 呼吸光晕
                if (glow > 0)
                  Container(
                    width: widget.size * (1.0 + 0.12 * breath),
                    height: widget.size * (1.0 + 0.12 * breath),
                    decoration: ShapeDecoration(
                      color: brand.withValues(alpha: glow),
                      shape: AppShape.circle,
                    ),
                  ),
                // 主按钮（波浪圆）
                Transform.rotate(
                  angle: _spin.value * 2 * math.pi,
                  child: ShapeBadge(
                    shape: MaterialShapes.cookie9Sided,
                    color: fill,
                    size: widget.size * 0.92,
                    child: widget.connecting
                        ? SizedBox.square(
                            dimension: widget.size * 0.22,
                            child: const CircularProgressIndicator(
                              strokeWidth: 3,
                              color: Colors.white,
                            ),
                          )
                        : GlyphIcon(
                            AppGlyphs.power,
                            size: widget.size * 0.30,
                            color: widget.connected || widget.connecting
                                ? Colors.white
                                : colorScheme.onSurfaceVariant,
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 区块标题。
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        text,
        style: AppTextStyle.headline.of(context, emphasized: true),
      ),
    );
  }
}

/// 智能模式 / 全局模式 分段切换。
class _ModeSelector extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(
      patchClashConfigProvider.select((state) => state.mode),
    );
    // 首页只展示「智能模式(rule)」和「全局模式(global)」两项。
    final segments = <(Mode, String)>[
      (Mode.rule, '智能模式'),
      (Mode.global, '全局模式'),
    ];
    // 若当前是 direct，视为 rule。
    final value = mode == Mode.global ? Mode.global : Mode.rule;
    return SegmentedControl<Mode>(
      segments: segments,
      value: value,
      onChanged: (m) {
        ref.read(setupActionProvider.notifier).changeMode(m);
      },
    );
  }
}

/// 当前节点卡片：国旗 + 节点名 + 延迟。
class _NodeCard extends ConsumerWidget {
  const _NodeCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final state = ref.watch(realSelectedProxyStateProvider(routedOutbound));
    final proxyName = state.proxyName;
    final delay = ref.watch(
      delayProvider(proxyName: proxyName, testUrl: null),
    );
    final flag = _flagOf(proxyName);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: ShapeDecoration(
          color: context.raisedSurfaceLevel.colorOf(colorScheme),
          shape: AppShape.all(AppCorner.lg),
          shadows: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Text(
              flag,
              style: const TextStyle(fontSize: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '当前节点',
                    style: AppTextStyle.caption1.of(context).copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    proxyName.isEmpty ? '未选择' : proxyName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.subheadline.of(context, emphasized: true),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _DelayBadge(delay: delay),
            const SizedBox(width: 4),
            GlyphIcon(
              AppGlyphs.chevronForward,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// 延迟徽标：<150 绿，150-300 黄，>300 红。
class _DelayBadge extends StatelessWidget {
  const _DelayBadge({required this.delay});

  final int? delay;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final d = delay;
    final (text, color) = switch (d) {
      null => ('—', colorScheme.onSurfaceVariant),
      < 0 => ('超时', colorScheme.error),
      < 150 => ('$d ms', const Color(0xFF22C55E)), // 绿
      < 300 => ('$d ms', const Color(0xFFF59E0B)), // 黄
      _ => ('$d ms', const Color(0xFFEF4444)), // 红
    };
    return Text(
      text,
      style: AppTextStyle.caption1.of(context, emphasized: true).copyWith(
        color: color,
      ),
    );
  }
}

/// 根据节点名匹配国旗 emoji。
String _flagOf(String name) {
  final lower = name.toLowerCase();
  const map = <String, String>{
    '香港': '🇭🇰',
    'hongkong': '🇭🇰',
    '日本': '🇯🇵',
    'japan': '🇯🇵',
    '新加坡': '🇸🇬',
    'singapore': '🇸🇬',
    '美国': '🇺🇸',
    'united states': '🇺🇸',
    'us ': '🇺🇸',
    '台湾': '🇨🇳',
    'taiwan': '🇨🇳',
    '韩国': '🇰🇷',
    'korea': '🇰🇷',
    '英国': '🇬🇧',
    'uk': '🇬🇧',
    '德国': '🇩🇪',
    'germany': '🇩🇪',
    '法国': '🇫🇷',
    'france': '🇫🇷',
    '加拿大': '🇨🇦',
    'canada': '🇨🇦',
    '澳大利亚': '🇦🇺',
    'australia': '🇦🇺',
    '印度': '🇮🇳',
    'india': '🇮🇳',
    '泰国': '🇹🇭',
    'thailand': '🇹🇭',
    '越南': '🇻🇳',
    'vietnam': '🇻🇳',
    '俄罗斯': '🇷🇺',
    'russia': '🇷🇺',
  };
  for (final entry in map.entries) {
    if (lower.contains(entry.key.toLowerCase())) {
      return entry.value;
    }
  }
  return '🌐';
}
