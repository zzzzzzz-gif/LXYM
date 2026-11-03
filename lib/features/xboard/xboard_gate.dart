import 'dart:async';
import 'dart:io';

import 'package:fl_clash/features/xboard/xboard_api.dart';
import 'package:fl_clash/features/xboard/xboard_remote_config.dart';
import 'package:fl_clash/features/xboard/xboard_session.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shows the Xboard login page until the user signs in, then [child].
class XboardGate extends ConsumerStatefulWidget {
  const XboardGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<XboardGate> createState() => _XboardGateState();
}

class _XboardGateState extends ConsumerState<XboardGate> {
  @override
  void initState() {
    super.initState();
    unawaited(restoreXboardSession());
    unawaited(xboardRemoteConfig.load());
    _listenThemeColor();
    // 已登录用户启动时也检查版本更新（延迟到配置加载完成）。
    unawaited(_checkUpdateOnStartup());
  }

  Future<void> _checkUpdateOnStartup() async {
    await xboardRemoteConfig.load();
    if (!mounted) return;
    if (xboardLoggedIn.value == true) {
      _checkUpdate();
    }
  }

  /// 监听远程配置的主题色，变化时更新主题。
  void _listenThemeColor() {
    void apply(XboardRemoteConfig next) {
      final color = next.themeColor;
      if (color == null) return;
      final current = ref.read(themeSettingProvider).primaryColor;
      if (current == null || current != color.toARGB32()) {
        ref
            .read(themeSettingProvider.notifier)
            .update((s) => s.copyWith(primaryColor: color.toARGB32()));
      }
    }

    apply(xboardRemoteConfig.config.value);
    xboardRemoteConfig.config.addListener(() {
      apply(xboardRemoteConfig.config.value);
    });
  }

  Future<void> _onLoggedIn(String auth, XboardSubscribe subscribe) async {
    await saveXboardSession(auth);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(syncXboardProfile(ref, subscribe.subscribeUrl));
      _checkUpdate();
    });
  }

  /// 版本更新检查：低于 minVersion 强制更新，低于 latestVersion 提示更新。
  void _checkUpdate() {
    final config = xboardRemoteConfig.config.value;
    final current = globalState.packageInfo.version;
    final minVersion = config.minVersion;
    final latestVersion = config.latestVersion;
    if (minVersion.isNotEmpty &&
        compareXboardVersion(current, minVersion) < 0) {
      // 强制更新：不可关闭。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showForceUpdateDialog(config);
      });
      return;
    }
    if (latestVersion.isNotEmpty &&
        compareXboardVersion(current, latestVersion) < 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showUpdateDialog(config);
      });
    }
  }

  String get _downloadUrl {
    final config = xboardRemoteConfig.config.value;
    if (Platform.isAndroid) return config.downloadUrls['android'] ?? '';
    if (Platform.isWindows) return config.downloadUrls['windows'] ?? '';
    if (Platform.isMacOS) return config.downloadUrls['mac'] ?? '';
    if (Platform.isIOS) return config.downloadUrls['ios'] ?? '';
    return '';
  }

  void _showForceUpdateDialog(XboardRemoteConfig config) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('版本过低'),
          content: Text(config.updateNote.isEmpty ? '请更新到最新版本后继续使用' : config.updateNote),
          actions: [
            TextButton(
              onPressed: () => _openDownload(config),
              child: const Text('立即更新'),
            ),
          ],
        ),
      ),
    );
  }

  void _showUpdateDialog(XboardRemoteConfig config) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('发现新版本'),
        content: Text(config.updateNote.isEmpty ? '有新版本可用' : config.updateNote),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('稍后再说'),
          ),
          TextButton(
            onPressed: () => _openDownload(config),
            child: const Text('立即更新'),
          ),
        ],
      ),
    );
  }

  Future<void> _openDownload(XboardRemoteConfig config) async {
    final url = _downloadUrl;
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri != null && uri.hasScheme) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool?>(
      valueListenable: xboardLoggedIn,
      builder: (context, loggedIn, _) {
        if (loggedIn == null) {
          return const Scaffold(body: SizedBox.shrink());
        }
        if (loggedIn) {
          return widget.child;
        }
        return XboardLoginPage(onLoggedIn: _onLoggedIn);
      },
    );
  }
}

class XboardLoginPage extends StatefulWidget {
  const XboardLoginPage({super.key, required this.onLoggedIn});

  final Future<void> Function(String auth, XboardSubscribe subscribe)
  onLoggedIn;

  @override
  State<XboardLoginPage> createState() => _XboardLoginPageState();
}

class _XboardLoginPageState extends State<XboardLoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = '请输入邮箱和密码');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = await xboardApi.login(email, password);
      final subscribe = await xboardApi.getSubscribe(auth);
      await widget.onLoggedIn(auth, subscribe);
    } on XboardException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '登录失败，请稍后再试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.hasScheme) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    xboardProfileLabel,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '登录你的账号',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _emailController,
                    enabled: !_loading,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: '邮箱'),
                  ),
                  const SizedBox(height: 16),
                  SecretTextFormField(
                    controller: _passwordController,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(labelText: '密码'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _loading
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('登录'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<XboardRemoteConfig>(
                    valueListenable: xboardRemoteConfig.config,
                    builder: (context, config, _) {
                      final showRegister =
                          config.registerEnabled && config.registerUrl.isNotEmpty;
                      final showForgot = config.forgotUrl.isNotEmpty;
                      if (!showRegister && !showForgot) {
                        return const SizedBox.shrink();
                      }
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (showRegister)
                            TextButton(
                              onPressed: () => _openUrl(config.registerUrl),
                              child: const Text('注册账号'),
                            ),
                          if (showRegister && showForgot)
                            const Text('·'),
                          if (showForgot)
                            TextButton(
                              onPressed: () => _openUrl(config.forgotUrl),
                              child: const Text('忘记密码'),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
