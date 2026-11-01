import 'dart:async';

import 'package:fl_clash/features/xboard/xboard_api.dart';
import 'package:fl_clash/features/xboard/xboard_session.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

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
  }

  Future<void> _onLoggedIn(String auth, XboardSubscribe subscribe) async {
    await saveXboardSession(auth);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(syncXboardProfile(ref, subscribe.subscribeUrl));
    });
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
