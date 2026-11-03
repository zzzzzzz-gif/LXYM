import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/xboard/xboard_remote_config.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/proxies/proxies.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// 品牌强调色。
const _brandColor = Color(0xFF2563EB);

/// 三态颜色。
const _idleColor = Color(0xFF5B6496); // 灰蓝
const _connectingColor = Color(0xFFD6AA28); // 琥珀
const _connectedColor = Color(0xFF2EAA50); // 绿

const _noticeIdKey = 'xboard_notice_shown_id';

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

  XboardRemoteConfig _config = const XboardRemoteConfig();

  @override
  void initState() {
    super.initState();
    _config = xboardRemoteConfig.config.value;
    ref.listenManual(isStartProvider, (prev, next) {
      if (_pending && prev != next) {
        _clearPending();
      }
    });
    xboardRemoteConfig.config.addListener(_onConfigChanged);
    _maybeShowNoticePopup();
  }

  void _onConfigChanged() {
    if (mounted) setState(() => _config = xboardRemoteConfig.config.value);
  }

  /// 公告弹窗：noticePopup 为 true 且 noticeId 未展示过时弹一次。
  Future<void> _maybeShowNoticePopup() async {
    final config = xboardRemoteConfig.config.value;
    if (!config.noticePopup || config.noticeId.isEmpty) return;
    String? shown;
    try {
      final prefs = await SharedPreferences.getInstance();
      shown = prefs.getString(_noticeIdKey);
    } catch (_) {}
    if (shown == config.noticeId) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(config.noticeTitle.isEmpty ? '公告' : config.noticeTitle),
        content: Text(config.noticeContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_noticeIdKey, config.noticeId);
    } catch (_) {}
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
    xboardRemoteConfig.config.removeListener(_onConfigChanged);
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_pending) return;
    setState(() => _pending = true);
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
    final dark = colorScheme.brightness == Brightness.dark;
    final pageColor = dark ? const Color(0xFF15171E) : const Color(0xFFF5F7FA);
    final isStart = ref.watch(isStartProvider);
    final connecting = _pending;
    final connected = !connecting && isStart;
    final config = _config;
    return Scaffold(
      backgroundColor: pageColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TopBar(
                siteName: config.siteName,
                onService: config.supportUrl.isEmpty
                    ? null
                    : () => _openUrl(config.supportUrl),
              ),
              const SizedBox(height: 36),
              _ConnectButton(
                connecting: connecting,
                connected: connected,
                onTap: _toggle,
              ),
              if (config.homeText.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  config.homeText,
                  textAlign: TextAlign.center,
                  style: AppTextStyle.footnote.of(context).copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 36),
              _SectionTitle('选项'),
              const SizedBox(height: 8),
              _ModeCard(),
              const SizedBox(height: 24),
              if (config.noticeEnabled && config.noticeContent.isNotEmpty) ...[
                _NoticeCard(config: config),
                const SizedBox(height: 24),
              ],
              _SectionTitle('节点'),
              const SizedBox(height: 8),
              _NodeCard(onTap: () => _goToProxies()),
            ],
          ),
        ),
      ),
    );
  }

  void _goToProxies() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProxiesView()),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.hasScheme) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

/// 顶部栏：圆角 App 图标 + 站点名 + 右侧「客服」。
class _TopBar extends StatelessWidget {
  const _TopBar({required this.siteName, required this.onService});

  final String siteName;
  final VoidCallback? onService;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset(
            'assets/images/icon.png',
            width: 40,
            height: 40,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          siteName.isEmpty ? '蓝星云' : siteName,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const Spacer(),
        if (onService != null)
          TextButton.icon(
            onPressed: onService,
            icon: const GlyphIcon(AppGlyphs.account, size: 18),
            label: const Text('客服'),
          ),
      ],
    );
  }
}

/// 公告卡片（可折叠）。
class _NoticeCard extends StatefulWidget {
  const _NoticeCard({required this.config});

  final XboardRemoteConfig config;

  @override
  State<_NoticeCard> createState() => _NoticeCardState();
}

class _NoticeCardState extends State<_NoticeCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final dark = colorScheme.brightness == Brightness.dark;
    final cardColor = dark ? const Color(0xFF23252D) : Colors.white;
    final config = widget.config;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: ShapeDecoration(
        color: cardColor,
        shape: AppShape.all(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const GlyphIcon(AppGlyphs.info, size: 18, color: _brandColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  config.noticeTitle.isEmpty ? '公告' : config.noticeTitle,
                  style: AppTextStyle.subheadline.of(context, emphasized: true),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: GlyphIcon(
                  _expanded ? AppGlyphs.chevronUp : AppGlyphs.chevronDown,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (_expanded) ...[
            const SizedBox(height: 10),
            Text(
              config.noticeContent,
              style: AppTextStyle.footnote.of(context).copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 区块标题（小号灰字）。
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        text,
        style: AppTextStyle.caption1.of(context).copyWith(
          color: context.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 大圆形连接按钮（Hiddify 风格：正圆 + logo 染色 + 光晕）。
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
        ? '连接中...'
        : connected
        ? '已连接'
        : '点击连接';
    return Column(
      children: [
        _GlowButton(
          size: size,
          connecting: connecting,
          connected: connected,
          onTap: onTap,
        ),
        const SizedBox(height: 20),
        Text(
          label,
          style: AppTextStyle.title3.of(context, emphasized: true),
        ),
        const SizedBox(height: 10),
        if (connected)
          const _DelayLine()
        else if (connecting)
          const _DelayPlaceholder(),
      ],
    );
  }
}

/// 已连接时：Wi-Fi 图标 + 延迟。
class _DelayLine extends ConsumerWidget {
  const _DelayLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final state = ref.watch(realSelectedProxyStateProvider(routedOutbound));
    final proxyName = state.proxyName;
    final delay = ref.watch(
      delayProvider(proxyName: proxyName, testUrl: null),
    );
    final text = delay != null && delay > 0 ? '$delay ms' : '-- ms';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlyphIcon(AppGlyphs.wifi, size: 16, color: _connectedColor),
        const SizedBox(width: 6),
        Text(
          text,
          style: AppTextStyle.caption1.of(context, emphasized: true).copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 连接中：灰色圆角占位条。
class _DelayPlaceholder extends StatelessWidget {
  const _DelayPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 14,
      decoration: ShapeDecoration(
        color: context.colorScheme.surfaceContainerHighest,
        shape: AppShape.all(7),
      ),
    );
  }
}

/// 正圆按钮 + 光晕（Hiddify 风格）。
class _GlowButton extends StatefulWidget {
  const _GlowButton({
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
  State<_GlowButton> createState() => _GlowButtonState();
}

class _GlowButtonState extends State<_GlowButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
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
  void didUpdateWidget(_GlowButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connecting != widget.connecting ||
        oldWidget.connected != widget.connected) {
      _updateAnimation();
    }
  }

  void _updateAnimation() {
    if (widget.connecting) {
      _breath.forward(from: 0);
    } else {
      _breath.stop();
      _breath.value = 0;
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  Color get _stateColor {
    if (widget.connecting) return _connectingColor;
    if (widget.connected) return _connectedColor;
    return _idleColor;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final color = _stateColor;
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _breath,
        builder: (context, child) {
          // 光晕透明度：未连接很淡，连接中 0.3↔0.8 呼吸，已连接常亮。
          double glowAlpha;
          if (widget.connecting) {
            glowAlpha = 0.3 + 0.5 * _breath.value;
          } else if (widget.connected) {
            glowAlpha = 0.5;
          } else {
            glowAlpha = 0.18;
          }
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: colorScheme.surface,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: glowAlpha),
                  blurRadius: 30,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Center(
              child: Image.asset(
                'assets/images/logo_mono.png',
                width: widget.size * 0.5,
                height: widget.size * 0.5,
                color: color,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 「选项」卡片：分段切换 + 右侧箭头。
class _ModeCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final dark = colorScheme.brightness == Brightness.dark;
    final cardColor = dark ? const Color(0xFF23252D) : Colors.white;
    return Container(
      decoration: ShapeDecoration(
        color: cardColor,
        shape: AppShape.all(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: _ModeSegments(),
            ),
          ),
          // 右侧蓝色圆圈箭头 → 打开选项页
          GestureDetector(
            onTap: () => _openOptions(context),
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              child: Container(
                width: 30,
                height: 30,
                decoration: ShapeDecoration(
                  color: _brandColor,
                  shape: AppShape.circle,
                ),
                child: const GlyphIcon(
                  AppGlyphs.chevronForward,
                  size: 16,
                  color: Color(0xFFFFFFFF),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openOptions(BuildContext context) {
    showSheet<void>(
      context: context,
      builder: (_) => const _OptionsSheet(),
    );
  }
}

/// 分段切换「智能模式 / 全局模式」。
class _ModeSegments extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final mode = ref.watch(
      patchClashConfigProvider.select((state) => state.mode),
    );
    final value = mode == Mode.global ? Mode.global : Mode.rule;
    final segments = <(Mode, String)>[
      (Mode.rule, '智能模式'),
      (Mode.global, '全局模式'),
    ];
    final dark = colorScheme.brightness == Brightness.dark;
    final trackColor = dark
        ? colorScheme.surfaceContainerHigh
        : colorScheme.surfaceContainer;
    final selectedColor = dark
        ? colorScheme.surfaceContainerHighest
        : const Color(0xFFE4E9F2);
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: ShapeDecoration(color: trackColor, shape: AppShape.all(12)),
      child: Row(
        children: [
          for (final (m, label) in segments)
            Expanded(
              child: GestureDetector(
                onTap: () {
                  ref.read(setupActionProvider.notifier).changeMode(m);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    color: m == value ? selectedColor : Colors.transparent,
                    shape: AppShape.all(9),
                  ),
                  child: Text(
                    label,
                    style: AppTextStyle.footnote.of(context).copyWith(
                      color: m == value
                          ? colorScheme.onSurface
                          : colorScheme.onSurfaceVariant,
                      fontWeight: m == value ? FontWeight.bold : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 选项弹层：模式分组（真实生效的规则/全局模式）。
class _OptionsSheet extends ConsumerWidget {
  const _OptionsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(
      patchClashConfigProvider.select((state) => state.mode),
    );
    final value = mode == Mode.global ? Mode.global : Mode.rule;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: 20 + context.bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '选项',
            style: AppTextStyle.title2.of(context, emphasized: true),
          ),
          const SizedBox(height: 16),
          const _OptionsSectionTitle('模式'),
          const SizedBox(height: 8),
          _OptionRow(
            title: '智能模式',
            subtitle: '国内网站直连，国外网站走代理',
            selected: value == Mode.rule,
            onTap: () {
              ref.read(setupActionProvider.notifier).changeMode(Mode.rule);
              Navigator.of(context).pop();
            },
          ),
          _OptionRow(
            title: '全局模式',
            subtitle: '所有流量都通过代理',
            selected: value == Mode.global,
            onTap: () {
              ref.read(setupActionProvider.notifier).changeMode(Mode.global);
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}

class _OptionsSectionTitle extends StatelessWidget {
  const _OptionsSectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyle.caption1.of(context).copyWith(
        color: context.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final dark = colorScheme.brightness == Brightness.dark;
    final cardColor = dark
        ? colorScheme.surfaceContainerHigh
        : colorScheme.surfaceContainer;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: ShapeDecoration(color: cardColor, shape: AppShape.all(14)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyle.subheadline.of(context, emphasized: true),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTextStyle.caption2.of(context).copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const GlyphIcon(AppGlyphs.checkCircle, size: 22, color: _brandColor),
          ],
        ),
      ),
    );
  }
}

/// 节点卡片（heysocks 风格）：国旗方块 + 节点名 + 延迟。
class _NodeCard extends ConsumerWidget {
  const _NodeCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final dark = colorScheme.brightness == Brightness.dark;
    final cardColor = dark ? const Color(0xFF23252D) : Colors.white;
    final state = ref.watch(realSelectedProxyStateProvider(routedOutbound));
    final proxyName = state.proxyName;
    final delay = ref.watch(
      delayProvider(proxyName: proxyName, testUrl: null),
    );
    final flag = _flagOf(proxyName);
    final isAuto = proxyName.isEmpty || _isAutoSelect(proxyName);
    final subLabel = isAuto ? '智能推荐' : '当前节点';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: ShapeDecoration(
          color: cardColor,
          shape: AppShape.all(16),
        ),
        child: Row(
          children: [
            // 国旗方块（圆角 8）
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: dark
                    ? colorScheme.surfaceContainerHigh
                    : colorScheme.surfaceContainer,
                shape: AppShape.all(8),
              ),
              child: Text(flag, style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subLabel,
                    style: AppTextStyle.caption2.of(context).copyWith(
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
            // 右下角延迟
            _DelayBadge(delay: delay),
            const SizedBox(width: 10),
            // 右上角蓝色圆圈箭头
            Container(
              width: 26,
              height: 26,
              decoration: ShapeDecoration(
                color: _brandColor,
                shape: AppShape.circle,
              ),
              child: const GlyphIcon(
                AppGlyphs.chevronForward,
                size: 14,
                color: Color(0xFFFFFFFF),
              ),
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
      < 150 => ('$d ms', const Color(0xFF22C55E)),
      < 300 => ('$d ms', const Color(0xFFF59E0B)),
      _ => ('$d ms', const Color(0xFFEF4444)),
    };
    return Text(
      text,
      style: AppTextStyle.caption1.of(context, emphasized: true).copyWith(
        color: color,
      ),
    );
  }
}

bool _isAutoSelect(String name) {
  final lower = name.toLowerCase();
  return lower.contains('自动') ||
      lower.contains('auto') ||
      lower.contains('url-test') ||
      lower.contains('fallback');
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
