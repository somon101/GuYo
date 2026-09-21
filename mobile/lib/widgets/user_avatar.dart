import 'package:flutter/material.dart';
import '../api/api_client.dart';

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

  const UserAvatar({super.key, required this.avatarUrl, required this.login, this.size = 88});

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl;
    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          ApiClient.instance.mediaUrl(url),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _DefaultAvatar(login: login, size: size),
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
