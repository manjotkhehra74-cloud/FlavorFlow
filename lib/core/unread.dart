import 'package:flutter/foundation.dart';

/// Global unread-notification counter — the bell badge listens to this, so
/// "Mark all read" (or opening one) clears the badge INSTANTLY instead of
/// waiting for the next 20s poll.
class Unread {
  static final ValueNotifier<int> count = ValueNotifier<int>(0);

  static void set(int v) => count.value = v < 0 ? 0 : v;
  static void clear() => count.value = 0;
  static void dec() => count.value = count.value > 0 ? count.value - 1 : 0;
}
