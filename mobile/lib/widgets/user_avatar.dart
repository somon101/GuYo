import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'remote_image.dart';

/// A small, fixed palette of GuYo-toned gradients a generated avatar picks
/// from -- deterministically, by `login`, so the SAME user always gets the
/// same default avatar (never a random one on every rebuild), while
/// different users still end up visually distinct from each other.
const List<List<Color>> _avatarGradients = [
  [Color(0xFF6366F1), Color(0xFF4338CA)], // indigo
  [Color(0xFF8B5CF6), Color(0xFF6D28D9)], // violet
  [Color(0xFF06B6D4), Color(0xFF0E7490)], // cyan
  [Color(0xFFF59E0B), Color(0xFFB45309)], // amber
  [Color(0xFFEC4899), Color(0xFFBE185D)], // pink
  [Color(0xFF10B981), Color(0xFF047857)], // emerald
];

List<Color> _gradientFor(String login) {
  if (login.isEmpty) return _avatarGradients.first;
  final hash = login.codeUnits.fold<int>(0, (acc, c) => acc + c);
  return _avatarGradients[hash % _avatarGradients.length];
}

/// One user's avatar: their own uploaded photo if [avatarUrl] is set,
/// otherwise a generated default -- a soft gradient circle with the first
/// letter of [login], the same one every time for that login (see
/// `_gradientFor`). Used wherever a user's identity needs a small picture,
/// not just the Profile screen itself.
class UserAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String login;
  final double size;

  /// The season-pass frame the person wears (a key from [frameColors]), if any.
  final String? frame;

  const UserAvatar({super.key, required this.avatarUrl, required this.login, this.size = 88, this.frame});

  @override
  Widget build(BuildContext context) {
    final key = frame;
    if (key == null || key.isEmpty) return _plain();
    // The ring sits inside the same box, so layouts do not move.
    final ring = size * 0.07 < 2.5 ? 2.5 : size * 0.07;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(ring),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(colors: [...frameColors(key), frameColors(key).first]),
      ),
      child: Container(
        padding: EdgeInsets.all(ring * 0.35),
        decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.surface),
        child: UserAvatar(avatarUrl: avatarUrl, login: login, size: size - 2 * ring - ring * 0.7),
      ),
    );
  }

  Widget _plain() {
    final url = avatarUrl;
    if (url != null && url.isNotEmpty) {
      // RemoteImage persists this to disk the first time it loads, so every
      // later view of the SAME url -- a cold app restart included --
      // renders instantly from that local copy with no network round trip,
      // and still renders with no internet present. It also caps the
      // decode to roughly this widget's own on-screen size regardless of
      // the source photo's real resolution, which is what prevents the
      // jank a multi-megapixel camera photo caused decoding at full size
      // into a 96-logical-pixel circle -- and, unlike the previous
      // two-axis cap, it does so without squashing a portrait or
      // landscape photo into the square box before the crop.
      return ClipOval(
        child: RemoteImage(
          url: url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          fallbackBuilder: () => _DefaultAvatar(login: login, size: size),
        ),
      );
    }
    return _DefaultAvatar(login: login, size: size);
  }
}

class _DefaultAvatar extends StatelessWidget {
  final String login;
  final double size;
  const _DefaultAvatar({required this.login, required this.size});

  @override
  Widget build(BuildContext context) {
    final gradient = _gradientFor(login);
    final letter = login.isNotEmpty ? login[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [
          BoxShadow(color: gradient.last.withValues(alpha: 0.35), blurRadius: size * 0.25, offset: Offset(0, size * 0.06)),
        ],
      ),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(color: Colors.white, fontSize: size * 0.42, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// The colours of each avatar frame (the keys the server's FRAME_KEYS lists).
List<Color> frameColors(String key) {
  switch (key) {
    case 'aurora':
      return const [Color(0xFF6EE7B7), Color(0xFF60A5FA), Color(0xFFA78BFA)];
    case 'fire':
      return const [Color(0xFFFF7043), Color(0xFFFFB74D), Color(0xFFFF5252)];
    case 'ocean':
      return const [Color(0xFF38BDF8), Color(0xFF2563EB), Color(0xFF22D3EE)];
    case 'emerald':
      return const [Color(0xFF34D399), Color(0xFF059669), Color(0xFF6EE7B7)];
    case 'royal':
      return const [Color(0xFF8B5CF6), Color(0xFFFFD54F), Color(0xFF6D28D9)];
    case 'rose':
      return const [Color(0xFFF472B6), Color(0xFFFB7185), Color(0xFFFDA4AF)];
    case 'ice':
      return const [Color(0xFFBAE6FD), Color(0xFF7DD3FC), Color(0xFFE0F2FE)];
    default: // gold
      return const [Color(0xFFFFD54F), Color(0xFFFF9800), Color(0xFFFFE082)];
  }
}
