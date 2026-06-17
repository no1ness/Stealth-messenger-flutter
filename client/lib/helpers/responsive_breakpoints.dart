import 'package:flutter/material.dart';

/// Responsive breakpoint constants for the Stealth design system.
class ResponsiveBreakpoints {
  ResponsiveBreakpoints._();

  /// Mobile-first: up to this width the UI is single-column.
  static const double mobileMaxWidth = 600.0;

  /// Tablet: between [mobileMaxWidth] + 1 and this width.
  static const double tabletMaxWidth = 960.0;

  /// Desktop: anything wider than [tabletMaxWidth].
  static const double desktopMinWidth = 961.0;

  /// Returns the device type for a given [width].
  static DeviceType deviceType(double width) {
    if (width <= mobileMaxWidth) return DeviceType.mobile;
    if (width <= tabletMaxWidth) return DeviceType.tablet;
    return DeviceType.desktop;
  }

  /// Shorthand for `deviceType(width) == DeviceType.desktop`.
  static bool isDesktop(double width) => width >= desktopMinWidth;

  /// Shorthand for `deviceType(width) == DeviceType.mobile`.
  static bool isMobile(double width) => width <= mobileMaxWidth;

  /// Shorthand for `deviceType(width) == DeviceType.tablet`.
  static bool isTablet(double width) =>
      !isMobile(width) && !isDesktop(width);
}

/// Semantic device-type enum.
enum DeviceType { mobile, tablet, desktop }
