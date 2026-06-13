import 'package:flutter/material.dart';
import 'package:golden_toolkit/golden_toolkit.dart';

/// Project-wide configuration for `golden_toolkit`.
///
/// Loaded once per test file via `setUpAll(() async { await
/// loadAppFonts(); })` or implicitly through `testGoldens` — both
/// suffice for fonts.
///
/// Why this lives in a helper:
///
/// - **Font loading.** Skia on CI (Linux) does not have our Geist /
///   Geist Mono custom fonts available system-wide. Without
///   `loadAppFonts()` the snapshots fall back to whatever
///   monospace/sans Skia happens to have, producing different bytes
///   on CI vs a dev machine. `loadAppFonts()` reads the assets
///   declared in `pubspec.yaml` and registers them with the Flutter
///   font loader so renders are consistent.
///
/// - **Device frame matrix.** Most golden tests should run at two
///   common widths (phone, tablet) so layout regressions on either
///   surface show up in the diff. Helpers below codify the two
///   frames we use.
Future<void> ensureGoldenFontsLoaded() async {
  await loadAppFonts();
}

/// Common phone-size frame for golden tests.
const Device kPhoneDevice = Device(
  name: 'phone',
  size: Size(390, 844),
  devicePixelRatio: 2,
);

/// Common tablet-size frame for golden tests.
const Device kTabletDevice = Device(
  name: 'tablet',
  size: Size(820, 1180),
  devicePixelRatio: 2,
);
