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

  /// The dark theme is on (see theme/app_theme.dart). Every colour below
  /// has a light and a dark value; the app rebuilds when this changes.
  static bool dark = false;

  /// Cards, sheets and tiles: white in the light theme.
  static Color get surface => dark ? const Color(0xFF1C1F2E) : Colors.white;

  static Color get primary => dark ? const Color(0xFF7C84F0) : const Color(0xFF5862DD);
  static Color get primaryDark => dark ? const Color(0xFFE9EBFA) : const Color(0xFF101B63);
  static Color get secondaryText => dark ? const Color(0xFF9AA3CC) : const Color(0xFF7180B0);
  static Color get success => dark ? const Color(0xFF2FCB86) : const Color(0xFF0A9C5D);
  static Color get successLight => dark ? const Color(0xFF143327) : const Color(0xFFE8F8F1);

  /// The one red in the palette -- a wrong answer, a destructive action.
  /// Kept as sparingly used as [success]: most of the app has no reason
  /// to ever need it.
  static Color get danger => dark ? const Color(0xFFFF6B70) : const Color(0xFFE0454B);
  static Color get dangerLight => dark ? const Color(0xFF3A1D22) : const Color(0xFFFCEAEA);

  // --- Surfaces -------------------------------------------------------------

  /// The app background behind every card: barely-there lavender, so white
  /// cards read as raised without needing heavy shadows.
  static Color get canvas => dark ? const Color(0xFF11131C) : const Color(0xFFF8F8FD);

  /// The soft violet fill used for icon chips, section pills and any
  /// "quiet" panel that still needs to stand apart from the canvas.
  static Color get violetSurface => dark ? const Color(0xFF262A46) : const Color(0xFFEEF0FF);

  /// Hairline border on white cards.
  static Color get cardBorder => dark ? const Color(0xFF2A2E45) : const Color(0xFFEDEFF7);

  /// Track behind every progress bar.
  static Color get progressTrack => dark ? const Color(0xFF2C3150) : const Color(0xFFE4E7F5);

  /// Chevrons and other low-emphasis glyphs.
  static Color get muted => dark ? const Color(0xFF5A6188) : const Color(0xFFB9BEDA);

  // --- Accents --------------------------------------------------------------

  /// GuYo's one yellow: stars, points and reward icons, trophies, and the
  /// fill of reward/Premium badges. Deliberately never used for text or
  /// numbers -- on white it is too light to read; those use [rewardText].
  static const Color gold = Color(0xFFFFEB3B);

  /// Reward badges ("⭐ +20"): a [gold] fill with [rewardText] on it.
  static const Color rewardBackground = gold;

  /// Text, numbers and icons that sit ON a [gold] fill, and point numbers
  /// on white -- a dark gold, readable on both.
  static const Color rewardText = Color(0xFF7A5600);

  /// A quest's reward badge ("⭐ +10"): a bright green the [gold] star
  /// stands out on, with the number in white.
  static const List<Color> questRewardGradient = [Color(0xFF34D17F), Color(0xFF14A85C)];

  /// The Premium and promo banners' fill, fading into [gold].
  static const List<Color> premiumGradient = [Color(0xFFFFF59D), gold];

  /// The "квест дня" highlight -- the one warm accent in an otherwise cool
  /// palette, so the single featured quest stands out from the list below.
  static const List<Color> dailyQuestGradient = [Color(0xFFF74D8F), Color(0xFFB434C8)];

  /// The big season banner's fill.
  static List<Color> get bannerGradient =>
      dark ? const [Color(0xFF242845), Color(0xFF1F2340)] : const [Color(0xFFE6E9FC), Color(0xFFDCE0FA)];

  /// The home screen's season block -- the same family as the banner, a
  /// touch lighter so it sits calmly under the greeting.
  static List<Color> get seasonCardGradient =>
      dark ? const [Color(0xFF22263F), Color(0xFF1D2138)] : const [Color(0xFFE9EBFD), Color(0xFFDFE3FB)];
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
