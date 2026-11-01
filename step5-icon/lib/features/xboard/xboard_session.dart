import 'dart:async';

import 'package:fl_clash/features/xboard/xboard_api.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _authKey = 'xboard_auth_data';

final xboardApi = XboardApi();

/// null until restored from storage; then whether a user is signed in.
final xboardLoggedIn = ValueNotifier<bool?>(null);

String? _auth;

String? get xboardAuth => _auth;

Future<void> restoreXboardSession() async {
  String? auth;
  try {
    final prefs = await SharedPreferences.getInstance();
    auth = prefs.getString(_authKey);
  } catch (_) {
    auth = null;
  }
  _auth = auth != null && auth.isNotEmpty ? auth : null;
  xboardLoggedIn.value = _auth != null;
}

Future<void> saveXboardSession(String auth) async {
  _auth = auth;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_authKey, auth);
  } catch (_) {}
  xboardLoggedIn.value = true;
}

Future<void> clearXboardSession(WidgetRef ref) async {
  _auth = null;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_authKey);
  } catch (_) {}
  for (final profile in [...ref.read(profilesProvider)]) {
    if (profile.label == xboardProfileLabel) {
      await ref.read(profilesActionProvider.notifier).deleteProfile(profile.id);
    }
  }
  xboardLoggedIn.value = false;
}

/// Keeps exactly one app-managed profile pointing at [subscribeUrl].
Future<void> syncXboardProfile(
  WidgetRef ref,
  String subscribeUrl, {
  bool forceUpdate = false,
}) async {
  final action = ref.read(profilesActionProvider.notifier);
  final managed = [
    for (final profile in ref.read(profilesProvider))
      if (profile.label == xboardProfileLabel) profile,
  ];
  if (managed.isEmpty) {
    await action.addProfileFromLink(subscribeUrl, label: xboardProfileLabel);
    return;
  }
  for (final extra in managed.skip(1)) {
    await action.deleteProfile(extra.id);
  }
  final profile = managed.first;
  if (profile.url != subscribeUrl || forceUpdate) {
    await action.updateProfile(
      profile.copyWith(url: subscribeUrl),
      showLoading: true,
    );
  }
}
