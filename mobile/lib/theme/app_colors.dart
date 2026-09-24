import 'package:flutter/material.dart';

/// GuYo's design tokens.
///
/// Started life as a few colors for the "Уроки" redesign and is now the
/// single palette every redesigned screen draws from -- Уроки, Профиль,
/// the shared word card, and the Главная/Квесты сезона surfaces built to
/// the latest visual reference. Anything new in those sections must take
/// its colors from here rather than inventing its own shade, so the whole
/// app keeps moving in one visual direction.
///
/// Deliberately NOT swapped in as the app's global ColorScheme seed: these
/// are explicit choices applied where a screen has been designed, not a
/// blanket recolor of everything that hasn't been.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF5862DD);
  static const Color primaryDark = Color(0xFF101B63);
  static const Color secondaryText = Color(0xFF7180B0);
  static const Color success = Color(0xFF0A9C5D);
  static const Color successLight = Color(0xFFE8F8F1);

  // --- Surfaces -------------------------------------------------------------

  /// The app background behind every card: barely-there lavender, so white
  /// cards read as raised without needing heavy shadows.
  static const Color canvas = Color(0xFFF8F8FD);

  /// The soft violet fill used for icon chips, section pills and any
  /// "quiet" panel that still needs to stand apart from the canvas.
  static const Color violetSurface = Color(0xFFEEF0FF);

  /// Hairline border on white cards.
  static const Color cardBorder = Color(0xFFEDEFF7);

  /// Track behind every progress bar.
  static const Color progressTrack = Color(0xFFE4E7F5);

  /// Chevrons and other low-emphasis glyphs.
  static const Color muted = Color(0xFFB9BEDA);

  // --- Accents --------------------------------------------------------------

  /// Reward badges ("⭐ +20").
  static const Color rewardBackground = Color(0xFFFFF3CD);
  static const Color rewardText = Color(0xFFB77A0B);

  /// The "квест дня" highlight -- the one warm accent in an otherwise cool
  /// palette, so the single featured quest stands out from the list below.
  static const List<Color> dailyQuestGradient = [Color(0xFFF74D8F), Color(0xFFB434C8)];

  /// The big season banner's fill.
  static const List<Color> bannerGradient = [Color(0xFFE6E9FC), Color(0xFFDCE0FA)];

  /// The home screen's season block -- the same family as the banner, a
  /// touch lighter so it sits calmly under the greeting.
  static const List<Color> seasonCardGradient = [Color(0xFFE9EBFD), Color(0xFFDFE3FB)];
}

/// Shape and elevation tokens that go with [AppColors]. Kept together so a
/// new card in these sections inherits the same geometry by construction
/// rather than by someone remembering the numbers.
class AppShapes {
  AppShapes._();

  /// Big feature surfaces: the season banner, the season block on Главная.
  static const double bannerRadius = 24;

  /// Ordinary content cards.
  static const double cardRadius = 20;

  /// Rows inside a card (one quest, one word).
  static const double rowRadius = 16;

  /// Pills, chips and badges.
  static const double pillRadius = 30;

  /// The one card shadow in this design language: barely visible, just
  /// enough to lift white off the lavender canvas.
  static List<BoxShadow> get cardShadow => [
        BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 12, offset: const Offset(0, 4)),
      ];
}
