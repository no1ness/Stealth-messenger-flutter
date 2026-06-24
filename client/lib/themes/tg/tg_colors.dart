import 'package:flutter/material.dart';
import 'package:stealth/logging/logger.dart';

class TgThemeColors {
  static final Map<int, TgThemeColors> _instances = {};

  static TgThemeColors of(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return _instances.putIfAbsent(
      brightness.index,
      () {
        Logger.debug('TgThemeColors: initialized 80+ color tokens');
        return TgThemeColors._fromBrightness(brightness);
      },
    );
  }

  static TgThemeColors get light => _light();
  static TgThemeColors get dark => _dark();

  static TgThemeColors _fromBrightness(Brightness brightness) {
    if (brightness == Brightness.light) return _light();
    return _dark();
  }

  static TgThemeColors _light() {
    return TgThemeColors._(
      primary: const Color(0xFF3390EC),
      primaryOpacity: const Color(0x1E50A2E9),
      primaryOpacityHover: const Color(0x4050A2E9),
      primaryShade: const Color(0xFF4A95D6),
      background: const Color(0xFFFFFFFF),
      backgroundCompactMenu: const Color(0xBBFFFFFF),
      backgroundCompactMenuHover: const Color(0x11000000),
      backgroundSecondary: const Color(0xFFF4F4F5),
      backgroundSecondaryAccent: const Color(0xFFE4E4E5),
      backgroundSidebar: const Color(0xFFE4E4E5),
      backgroundOwn: const Color(0xFFEEFFDE),
      backgroundOwnApple: const Color(0xFFDCF8C5),
      backgroundSelected: const Color(0xFFF4F4F5),
      backgroundOwnSelected: const Color(0xFFD0FFAC),
      text: const Color(0xFF000000),
      textSecondary: const Color(0xFF707579),
      iconSecondary: const Color(0xFF707579),
      textSecondaryApple: const Color(0xFF8E8E92),
      textMeta: const Color(0xFF686C72),
      textMetaColored: const Color(0xFF4FAE4E),
      messageMetaOwn: const Color(0xFF4FAE4E),
      borders: const Color(0xFFDADCE0),
      bordersInput: const Color(0xFFDADCE0),
      dividers: const Color(0xFFC8C6CC),
      dividersAndroid: const Color(0xFFE7E7E7),
      links: const Color(0xFF3390EC),
      ownLinks: const Color(0xFF3390EC),
      gray: const Color(0xFFC4C9CC),
      listIcon: const Color(0xFFABAFB1),
      defaultShadow: const Color(0x40727272),
      lightShadow: const Color(0x2B727272),
      active: const Color(0xFF00C73E),
      activeDarker: const Color(0xFF00A734),
      green: const Color(0xFF00C73E),
      greenDarker: const Color(0xFF00A734),
      success: const Color(0xFF00C73E),
      accentOwn: const Color(0xFF45AF54),
      code: const Color(0xFF4A729A),
      codeOwn: const Color(0xFF3C7940),
      codeBg: const Color(0x14707579),
      codeOwnBg: const Color(0x14707579),
      composerButton: const Color(0xCC707579),
      replyHover: const Color(0xFFF4F4F4),
      replyActive: const Color(0xFFE8E9E9),
      replyOwnHover: const Color(0xFFD9F5CE),
      replyOwnActive: const Color(0xFFC5ECBE),
      chatHover: const Color(0xFFF4F4F5),
      chatActive: const Color(0xFF3390EC),
      chatActiveGreyed: const Color(0xFF60A7F0),
      chatUsername: const Color(0xFF3C7EB0),
      itemHover: const Color(0xFFF4F4F5),
      itemActive: const Color(0xFFEDEDED),
      hoverOverlay: const Color(0x06000000),
      toastBackground: const Color(0xCC202020),
      messageReaction: const Color(0xFFEBF3FD),
      messageReactionHover: const Color(0xFFC5DEF9),
      messageReactionOwn: const Color(0xFFC6EAB2),
      messageReactionHoverOwn: const Color(0xFFB5E0A4),
      messageReactionChosenHover: const Color(0xFF1A82EA),
      messageReactionChosenHoverOwn: const Color(0xFF3F9D4B),
      messageNonContact: const Color(0xFFCCEEBF),
      voiceTranscribeButton: const Color(0xFFE8F3FF),
      voiceTranscribeButtonOwn: const Color(0xFFCCEEBF),
      backgroundMenuSeparator: const Color(0x1A000000),
      skeletonBackground: const Color(0x26151515),
      skeletonForeground: const Color(0x33E8E8E8),
      scrollbar: const Color(0x4D5A5A5A),
      error: const Color(0xFFE53935),
      warning: const Color(0xFFFB8C00),
      surface: const Color(0xFFFFFFFF),
      cardBackground: const Color(0xFFFFFFFF),
      divider: const Color(0xFFC8C6CC),
    );
  }

  static TgThemeColors _dark() {
    return TgThemeColors._(
      primary: const Color(0xFF8774E1),
      primaryOpacity: const Color(0x1E8378DB),
      primaryOpacityHover: const Color(0x408378DB),
      primaryShade: const Color(0xFF7B71C6),
      background: const Color(0xFF212121),
      backgroundCompactMenu: const Color(0xDD212121),
      backgroundCompactMenuHover: const Color(0x66000000),
      backgroundSecondary: const Color(0xFF0F0F0F),
      backgroundSecondaryAccent: const Color(0xFF191919),
      backgroundSidebar: const Color(0xFF0F0F0F),
      backgroundOwn: const Color(0xFF766AC8),
      backgroundOwnApple: const Color(0xFF766AC8),
      backgroundSelected: const Color(0xFF2C2C2C),
      backgroundOwnSelected: const Color(0xFF6549D4),
      text: const Color(0xFFFFFFFF),
      textSecondary: const Color(0xFFAAAAAA),
      iconSecondary: const Color(0xFFAAAAAA),
      textSecondaryApple: const Color(0xFFAAAAAA),
      textMeta: const Color(0xFFAAAAAA),
      textMetaColored: const Color(0xFF8378DB),
      messageMetaOwn: const Color(0x88FFFFFF),
      borders: const Color(0xFF303030),
      bordersInput: const Color(0xFF5B5B5A),
      dividers: const Color(0xFF3B3B3D),
      dividersAndroid: const Color(0xFF0F0F0F),
      links: const Color(0xFF8774E1),
      ownLinks: const Color(0xFFFFFFFF),
      gray: const Color(0xFF717579),
      listIcon: const Color(0xFFA2A2A2),
      defaultShadow: const Color(0x9C101010),
      lightShadow: const Color(0x40000000),
      active: const Color(0xFF8774E1),
      activeDarker: const Color(0xFF7B71C6),
      green: const Color(0xFF00C73E),
      greenDarker: const Color(0xFF00A734),
      success: const Color(0xFF00C73E),
      accentOwn: const Color(0xFFFFFFFF),
      code: const Color(0xFF8774E1),
      codeOwn: const Color(0xFFFFFFFF),
      codeBg: const Color(0x80000000),
      codeOwnBg: const Color(0x50000000),
      composerButton: const Color(0xCCAAAAAA),
      replyHover: const Color(0xFF272727),
      replyActive: const Color(0xFF2E2F2F),
      replyOwnHover: const Color(0xFF8775DA),
      replyOwnActive: const Color(0xFF917DEA),
      chatHover: const Color(0xFF2C2C2C),
      chatActive: const Color(0xFF766AC8),
      chatActiveGreyed: const Color(0xFF9288D3),
      chatUsername: const Color(0xFFE9EEF4),
      itemHover: const Color(0xFF2C2C2C),
      itemActive: const Color(0xFF292929),
      hoverOverlay: const Color(0x06FFFFFF),
      toastBackground: const Color(0xCC000000),
      messageReaction: const Color(0xFF2B2A35),
      messageReactionHover: const Color(0xFF343147),
      messageReactionOwn: const Color(0xFF675CAF),
      messageReactionHoverOwn: const Color(0xFF5B529B),
      messageReactionChosenHover: const Color(0xFF7864DD),
      messageReactionChosenHoverOwn: const Color(0xFFF5F5F5),
      messageNonContact: const Color(0xFFAAAAAA),
      voiceTranscribeButton: const Color(0xFF2A2A3C),
      voiceTranscribeButtonOwn: const Color(0xFF8373D3),
      backgroundMenuSeparator: const Color(0x1AFFFFFF),
      skeletonBackground: const Color(0x26212121),
      skeletonForeground: const Color(0x33E8E8E8),
      scrollbar: const Color(0x4D5A5A5A),
      error: const Color(0xFFEF5350),
      warning: const Color(0xFFFFA726),
      surface: const Color(0xFF212121),
      cardBackground: const Color(0xFF212121),
      divider: const Color(0xFF3B3B3D),
    );
  }

  const TgThemeColors._({
    required this.primary,
    required this.primaryOpacity,
    required this.primaryOpacityHover,
    required this.primaryShade,
    required this.background,
    required this.backgroundCompactMenu,
    required this.backgroundCompactMenuHover,
    required this.backgroundSecondary,
    required this.backgroundSecondaryAccent,
    required this.backgroundSidebar,
    required this.backgroundOwn,
    required this.backgroundOwnApple,
    required this.backgroundSelected,
    required this.backgroundOwnSelected,
    required this.text,
    required this.textSecondary,
    required this.iconSecondary,
    required this.textSecondaryApple,
    required this.textMeta,
    required this.textMetaColored,
    required this.messageMetaOwn,
    required this.borders,
    required this.bordersInput,
    required this.dividers,
    required this.dividersAndroid,
    required this.links,
    required this.ownLinks,
    required this.gray,
    required this.listIcon,
    required this.defaultShadow,
    required this.lightShadow,
    required this.active,
    required this.activeDarker,
    required this.green,
    required this.greenDarker,
    required this.success,
    required this.accentOwn,
    required this.code,
    required this.codeOwn,
    required this.codeBg,
    required this.codeOwnBg,
    required this.composerButton,
    required this.replyHover,
    required this.replyActive,
    required this.replyOwnHover,
    required this.replyOwnActive,
    required this.chatHover,
    required this.chatActive,
    required this.chatActiveGreyed,
    required this.chatUsername,
    required this.itemHover,
    required this.itemActive,
    required this.hoverOverlay,
    required this.toastBackground,
    required this.messageReaction,
    required this.messageReactionHover,
    required this.messageReactionOwn,
    required this.messageReactionHoverOwn,
    required this.messageReactionChosenHover,
    required this.messageReactionChosenHoverOwn,
    required this.messageNonContact,
    required this.voiceTranscribeButton,
    required this.voiceTranscribeButtonOwn,
    required this.backgroundMenuSeparator,
    required this.skeletonBackground,
    required this.skeletonForeground,
    required this.scrollbar,
    required this.error,
    required this.warning,
    required this.surface,
    required this.cardBackground,
    required this.divider,
  });

  final Color primary;
  final Color primaryOpacity;
  final Color primaryOpacityHover;
  final Color primaryShade;
  final Color background;
  final Color backgroundCompactMenu;
  final Color backgroundCompactMenuHover;
  final Color backgroundSecondary;
  final Color backgroundSecondaryAccent;
  final Color backgroundSidebar;
  final Color backgroundOwn;
  final Color backgroundOwnApple;
  final Color backgroundSelected;
  final Color backgroundOwnSelected;
  final Color text;
  final Color textSecondary;
  final Color iconSecondary;
  final Color textSecondaryApple;
  final Color textMeta;
  final Color textMetaColored;
  final Color messageMetaOwn;
  final Color borders;
  final Color bordersInput;
  final Color dividers;
  final Color dividersAndroid;
  final Color links;
  final Color ownLinks;
  final Color gray;
  final Color listIcon;
  final Color defaultShadow;
  final Color lightShadow;
  final Color active;
  final Color activeDarker;
  final Color green;
  final Color greenDarker;
  final Color success;
  final Color accentOwn;
  final Color code;
  final Color codeOwn;
  final Color codeBg;
  final Color codeOwnBg;
  final Color composerButton;
  final Color replyHover;
  final Color replyActive;
  final Color replyOwnHover;
  final Color replyOwnActive;
  final Color chatHover;
  final Color chatActive;
  final Color chatActiveGreyed;
  final Color chatUsername;
  final Color itemHover;
  final Color itemActive;
  final Color hoverOverlay;
  final Color toastBackground;
  final Color messageReaction;
  final Color messageReactionHover;
  final Color messageReactionOwn;
  final Color messageReactionHoverOwn;
  final Color messageReactionChosenHover;
  final Color messageReactionChosenHoverOwn;
  final Color messageNonContact;
  final Color voiceTranscribeButton;
  final Color voiceTranscribeButtonOwn;
  final Color backgroundMenuSeparator;
  final Color skeletonBackground;
  final Color skeletonForeground;
  final Color scrollbar;
  final Color error;
  final Color warning;
  final Color surface;
  final Color cardBackground;
  final Color divider;
}
