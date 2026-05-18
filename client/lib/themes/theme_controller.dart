import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:stealth/logging/logger.dart';

/// Lightweight broadcast channel for the app's [ThemeMode].
///
/// Why a top-level `ValueNotifier` and not Riverpod: this branch
/// (`feature/ui-design-refactor`) is forked from `main`, which does
/// not have Riverpod wired into the screen tree yet. The
/// `feature/hardening-di-secure-storage` branch introduces Riverpod;
/// on merge, swap this `ValueNotifier` for a `themeModeProvider`
/// without touching any screen-level code (the API surface stays
/// the same: read the current mode, write a new one, listen for
/// changes).
class ThemeController {
  ThemeController._();

  /// Single source of truth for the active [ThemeMode]. Widgets at
  /// the app root listen via `ValueListenableBuilder` and rebuild
  /// when this changes; screens that want to change the theme call
  /// [setMode].
  static final ValueNotifier<ThemeMode> mode =
      ValueNotifier<ThemeMode>(ThemeMode.dark);

  /// Load the persisted theme, applying the design-system v2
  /// backward-compat gate: fresh installs default to [ThemeMode.dark]
  /// (signature crypto-noir identity); users who already chose a
  /// preference keep it.
  static Future<ThemeMode> loadInitial() async {
    final prefs = await SharedPreferences.getInstance();
    final hasPersisted = prefs.containsKey('themeMode');
    if (hasPersisted) {
      final index = prefs.getInt('themeMode') ?? ThemeMode.dark.index;
      final resolved = ThemeMode.values[index];
      mode.value = resolved;
      Logger.info('[theme] resolved=$resolved persistedPref=true');
      return resolved;
    }
    mode.value = ThemeMode.dark;
    Logger.info('[theme] resolved=dark persistedPref=false (fresh install)');
    return ThemeMode.dark;
  }

  /// Set + persist the active theme mode. Callable from the Settings
  /// screen toggle.
  static Future<void> setMode(ThemeMode next) async {
    if (mode.value == next) {
      return;
    }
    Logger.info('[theme:set] mode=$next source=user-toggle');
    mode.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', next.index);
  }
}
