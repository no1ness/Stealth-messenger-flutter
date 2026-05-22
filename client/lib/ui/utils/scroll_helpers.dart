import 'package:flutter/material.dart';

/// Schedules an animated scroll-to-bottom on the next frame for the
/// given controller. No-ops if the controller has no clients yet
/// (e.g. ListView hasn't built). Extracted from `chats_screen.dart`
/// (FIX_PLAN Phase B).
void scheduleScrollToBottom(ScrollController controller) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (controller.hasClients) {
      controller.animateTo(
        controller.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  });
}
