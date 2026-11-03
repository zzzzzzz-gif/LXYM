import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

const _brandColor = Color(0xFF2563EB);

/// 提示节点的关键词：命中时置顶灰字展示，不可点击、不测速。
const _hintKeywords = [
  '官网',
  '网址',
  '订阅',
  '到期',
  '剩余',
  '过期',
  '流量',
  '重置',
];

const _regions = ['全部', '香港', '日本', '新加坡', '美国', '其他'];

/// 地区关键词，用于按地区筛选。
const _regionKeywords = <String, List<String>>{
  '香港': ['香港', 'hongkong', 'hong kong', 'hk'],
  '日本': ['日本', 'japan', 'jp', '东京', '大阪'],
  '新加坡': ['新加坡', 'singapore', 'sg'],
  '美国': ['美国', 'united states', 'usa', 'us ', '洛杉矶', '圣何塞', '西雅图'],
};

bool _isHintNode(String name) {
  final lower = name.toLowerCase();
  return _hintKeywords.any((k) => name.contains(k) || lower.contains(k));
}

String _regionOf(String name) {
  final lower = name.toLowerCase();
  for (final entry in _regionKeywords.entries) {
    if (entry.value.any((k) => lower.contains(k.toLowerCase()))) {
      return entry.key;
    }
  }
  return '其他';
}

/// 根据节点名匹配国旗 emoji。
String _flagOf(String name) {
  final lower = name.toLowerCase();
  const map = <String, String>{
    '香港': '🇭🇰',
    'hongkong': '🇭🇰',
    'hong kong': '🇭🇰',
    '日本': '🇯🇵',
    'japan': '🇯🇵',
    '新加坡': '🇸🇬',
    'singapore': '🇸🇬',
    '美国': '🇺🇸',
    'united states': '🇺🇸',
    '台湾': '🇨🇳',
    'taiwan': '🇨🇳',
    '韩国': '🇰🇷',
    'korea': '🇰🇷',
    '英国': '🇬🇧',
    'germany': '🇩🇪',
    '德国': '🇩🇪',
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

/// 节点列表页：直接列出站点分组的全部项。
class LanxingNodesPage extends ConsumerStatefulWidget {
  const LanxingNodesPage({super.key, required this.siteName});

  final String siteName;

  @override
  ConsumerState<LanxingNodesPage> createState() => _LanxingNodesPageState();
}

class _LanxingNodesPageState extends ConsumerState<LanxingNodesPage> {
  String _region = '全部';

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final dark = colorScheme.brightness == Brightness.dark;
    final pageColor = dark ? const Color(0xFF15171E) : const Color(0xFFF5F7FA);
    final cardColor = dark ? const Color(0xFF23252D) : Colors.white;
    final groups = ref.watch(groupsProvider);
    final site = widget.siteName.isEmpty ? '蓝星云' : widget.siteName;
    Group? group = groups.getGroup(site);
    if (group == null) {
      for (final g in groups) {
        if (g.type == GroupType.Selector) {
          group = g;
          break;
        }
      }
    }
    final groupName = group?.name ?? site;
    final testUrl = group?.testUrl;

    // 分类：提示节点、子分组（如自动选择）、真实节点。
    final hints = <Proxy>[];
    final subGroups = <Proxy>[];
    final realNodes = <Proxy>[];
    for (final proxy in group?.all ?? const <Proxy>[]) {
      if (_isHintNode(proxy.name)) {
        hints.add(proxy);
      } else if (GroupTypeExtension.getGroupType(proxy.type) != null ||
          groups.getGroup(proxy.name) != null) {
        subGroups.add(proxy);
      } else {
        realNodes.add(proxy);
      }
    }
    // 第一项固定「自动选择」：优先真实子分组，没有就用第一个 url-test 分组。
    final autoGroup = subGroups.isEmpty ? null : subGroups.first;
    final filtered = _region == '全部'
        ? realNodes
        : realNodes.where((p) => _regionOf(p.name) == _region).toList();
    final selectedName =
        ref.watch(selectedProxyNameProvider(groupName)) ?? '';

    return Scaffold(
      backgroundColor: pageColor,
      appBar: AppBar(
        backgroundColor: pageColor,
        elevation: 0,
        title: const Text('节点'),
        actions: [
          TextButton.icon(
            onPressed: () => _testAll(realNodes, testUrl),
            icon: const GlyphIcon(AppGlyphs.bolt, size: 18),
            label: const Text('测速'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: 120 + context.bottomInset,
        ),
        children: [
          // 地区筛选
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _regions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, index) {
                final region = _regions[index];
                final selected = region == _region;
                return GestureDetector(
                  onTap: () => setState(() => _region = region),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: ShapeDecoration(
                      color: selected ? _brandColor : cardColor,
                      shape: AppShape.all(10),
                    ),
                    child: Text(
                      region,
                      style: AppTextStyle.footnote.of(context).copyWith(
                        color: selected
                            ? const Color(0xFFFFFFFF)
                            : colorScheme.onSurfaceVariant,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.w400,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          // 提示节点（灰色小字，不可点）
          if (hints.isNotEmpty) ...[
            for (final hint in hints)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  hint.name,
                  style: AppTextStyle.caption2.of(context).copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
          // 自动选择
          if (autoGroup != null)
            _NodeRow(
              name: '自动选择',
              subtitle: _autoSubtitle(autoGroup.name),
              flag: '⚡',
              cardColor: cardColor,
              delay: null,
              selected: selectedName == autoGroup.name,
              onTap: () => _select(groupName, autoGroup.name),
            ),
          // 真实节点
          for (final proxy in filtered)
            _NodeRow(
              name: proxy.name,
              flag: _flagOf(proxy.name),
              cardColor: cardColor,
              delay: ref.watch(
                delayProvider(proxyName: proxy.name, testUrl: testUrl),
              ),
              selected: selectedName == proxy.name,
              onTap: () => _select(groupName, proxy.name),
            ),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  '该地区暂无节点',
                  style: AppTextStyle.footnote.of(context).copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 「自动选择」副标题：显示它当前选中的真实节点名。
  String _autoSubtitle(String autoGroupName) {
    final autoSelected =
        ref.watch(selectedProxyNameProvider(autoGroupName)) ?? '';
    if (autoSelected.isEmpty) return '自动挑选最优节点';
    final real = ref.watch(realSelectedProxyStateProvider(autoSelected));
    return real.proxyName.isEmpty ? '自动挑选最优节点' : real.proxyName;
  }

  void _select(String groupName, String proxyName) {
    ref
        .read(proxiesActionProvider.notifier)
        .changeProxyDebounce(groupName, proxyName);
    Navigator.of(context).pop();
  }

  void _testAll(List<Proxy> nodes, String? testUrl) {
    final action = ref.read(proxiesActionProvider.notifier);
    for (final proxy in nodes) {
      unawaited(action.proxyDelayTest(proxy, testUrl));
    }
  }
}

/// 节点行：国旗方块 + 名字（+副标题） + 延迟 + 选中对勾。
class _NodeRow extends StatelessWidget {
  const _NodeRow({
    required this.name,
    this.subtitle,
    required this.flag,
    required this.cardColor,
    required this.delay,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String? subtitle;
  final String flag;
  final Color cardColor;
  final int? delay;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final dark = colorScheme.brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: ShapeDecoration(color: cardColor, shape: AppShape.all(14)),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: dark
                    ? colorScheme.surfaceContainerHigh
                    : colorScheme.surfaceContainer,
                shape: AppShape.all(8),
              ),
              child: Text(flag, style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.subheadline.of(
                      context,
                      emphasized: true,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.caption2.of(context).copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _NodeDelay(delay: delay),
            if (selected) ...[
              const SizedBox(width: 8),
              const GlyphIcon(
                AppGlyphs.checkCircle,
                size: 20,
                color: _brandColor,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 延迟：<150 绿，150-300 黄，>300 红，未测速「--」。
class _NodeDelay extends StatelessWidget {
  const _NodeDelay({required this.delay});

  final int? delay;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final d = delay;
    final (text, color) = switch (d) {
      null || 0 => ('--', colorScheme.onSurfaceVariant),
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
