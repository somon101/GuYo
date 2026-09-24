import 'package:flutter/material.dart';

/// The part of the day the greeting's sky object reflects.
///
/// Decided entirely from the DEVICE's own clock -- never the server's. Two
/// people opening GuYo at the same instant in Dushanbe and in Berlin must
/// each see their own sky, so nothing here may go near a backend time.
enum DayPart { morning, day, evening, night }

/// One boundary in the day: this part begins at [startHour] local time and
/// runs until the next window starts.
class DayPartWindow {
  final DayPart part;

  /// Local hour, 0-23, at which this part begins.
  final int startHour;

  const DayPartWindow(this.part, this.startHour);
}

/// Where a moment in the day maps to a part.
///
/// The boundaries live here, in one list, precisely so they can be moved
/// without touching the widget that draws them -- change the hours (or
/// hand the greeting a different scheme entirely, e.g. one fetched from
/// the backend later) and everything downstream follows. The widget asks
/// "which part is it", never "what hour is it".
class TimeOfDayScheme {
  /// Windows in ascending start order. The last one wraps past midnight.
  final List<DayPartWindow> windows;

  const TimeOfDayScheme(this.windows);

  /// GuYo's default boundaries.
  static const standard = TimeOfDayScheme([
    DayPartWindow(DayPart.night, 0),
    DayPartWindow(DayPart.morning, 5),
    DayPartWindow(DayPart.day, 11),
    DayPartWindow(DayPart.evening, 17),
    DayPartWindow(DayPart.night, 22),
  ]);

  /// The part [at] falls in. Takes an explicit moment rather than reading
  /// the clock itself, so a test can pin it -- and so the caller is the
  /// one that decides the time is local (see [DayPartIcon]).
  DayPart partAt(DateTime at) {
    final hour = at.hour;
    var current = windows.first.part;
    for (final window in windows) {
      if (hour >= window.startHour) {
        current = window.part;
      } else {
        break;
      }
    }
    return current;
  }
}

/// How each part looks. Kept beside the scheme so adding a part means
/// adding one entry here and one window above -- nothing else changes.
const Map<DayPart, ({IconData icon, Color color, String label})> dayPartLooks = {
  DayPart.morning: (icon: Icons.wb_twilight_rounded, color: Color(0xFFF59E0B), label: 'Утро'),
  DayPart.day: (icon: Icons.light_mode_rounded, color: Color(0xFFFFB300), label: 'День'),
  DayPart.evening: (icon: Icons.nights_stay_rounded, color: Color(0xFF7C6FE8), label: 'Вечер'),
  DayPart.night: (icon: Icons.dark_mode_rounded, color: Color(0xFF4B54C9), label: 'Ночь'),
};

/// The sky object beside the greeting: a sun, a dusk sky or a moon,
/// depending on what time it is ON THIS DEVICE.
///
/// [now] exists only so tests can pin the clock; in the app it is left
/// null and the device's own local time is read.
class DayPartIcon extends StatelessWidget {
  final double size;
  final TimeOfDayScheme scheme;
  final DateTime? now;

  const DayPartIcon({
    super.key,
    this.size = 18,
    this.scheme = TimeOfDayScheme.standard,
    this.now,
  });

  @override
  Widget build(BuildContext context) {
    // DateTime.now() is the device's own local wall clock -- the whole
    // point of this widget. Nothing here consults the backend.
    final part = scheme.partAt(now ?? DateTime.now());
    final look = dayPartLooks[part]!;
    return Semantics(
      label: look.label,
      child: Icon(look.icon, size: size, color: look.color),
    );
  }
}
