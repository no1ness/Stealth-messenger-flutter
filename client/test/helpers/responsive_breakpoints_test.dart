import 'package:flutter_test/flutter_test.dart';

import 'package:stealth/helpers/responsive_breakpoints.dart';

void main() {
  group('ResponsiveBreakpoints constants', () {
    test('mobileMaxWidth is 600', () {
      expect(ResponsiveBreakpoints.mobileMaxWidth, 600.0);
    });

    test('tabletMaxWidth is 960', () {
      expect(ResponsiveBreakpoints.tabletMaxWidth, 960.0);
    });

    test('desktopMinWidth is 961', () {
      expect(ResponsiveBreakpoints.desktopMinWidth, 961.0);
    });
  });

  group('ResponsiveBreakpoints.deviceType', () {
    test('returns mobile for width <= 600', () {
      expect(ResponsiveBreakpoints.deviceType(0), DeviceType.mobile);
      expect(ResponsiveBreakpoints.deviceType(300), DeviceType.mobile);
      expect(ResponsiveBreakpoints.deviceType(600), DeviceType.mobile);
    });

    test('returns tablet for width 601-960', () {
      expect(ResponsiveBreakpoints.deviceType(601), DeviceType.tablet);
      expect(ResponsiveBreakpoints.deviceType(800), DeviceType.tablet);
      expect(ResponsiveBreakpoints.deviceType(960), DeviceType.tablet);
    });

    test('returns desktop for width >= 961', () {
      expect(ResponsiveBreakpoints.deviceType(961), DeviceType.desktop);
      expect(ResponsiveBreakpoints.deviceType(1440), DeviceType.desktop);
    });
  });

  group('ResponsiveBreakpoints shorthands', () {
    test('isMobile', () {
      expect(ResponsiveBreakpoints.isMobile(320), isTrue);
      expect(ResponsiveBreakpoints.isMobile(600), isTrue);
      expect(ResponsiveBreakpoints.isMobile(601), isFalse);
    });

    test('isDesktop', () {
      expect(ResponsiveBreakpoints.isDesktop(960), isFalse);
      expect(ResponsiveBreakpoints.isDesktop(961), isTrue);
      expect(ResponsiveBreakpoints.isDesktop(1920), isTrue);
    });

    test('isTablet', () {
      expect(ResponsiveBreakpoints.isTablet(320), isFalse);
      expect(ResponsiveBreakpoints.isTablet(800), isTrue);
      expect(ResponsiveBreakpoints.isTablet(961), isFalse);
    });
  });
}
