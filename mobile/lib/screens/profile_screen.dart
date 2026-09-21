import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../achievements/achievement_icons.dart';
import '../api/api_client.dart';
import '../models/user_profile.dart';
import '../widgets/user_avatar.dart';

/// "Профиль": the user's own identity (avatar, login, their permanent
/// user_id) plus their achievements -- both fetched from the backend, which
/// is the sole source of truth for whether an achievement is earned (see
/// backend/app/achievements/). This screen only renders what it's given
/// and uploads/removes an avatar file; nothing about earning logic lives
/// here.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

// Persisted locally purely so the unlock celebration is shown at most once
// per achievement, even across app restarts -- earning itself is already
// fully durable on the backend regardless of this; this is only "have I
// already shown the user this specific celebration".
const _seenAchievementsKey = 'guyo_seen_achievement_ids';
final _localStorage = FlutterSecureStorage();

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  String? _loadError;
  UserProfile? _profile;
  List<UserAchievement> _achievements = [];
  bool _isUpdatingAvatar = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        ApiClient.instance.fetchMyProfile(),
        ApiClient.instance.fetchMyAchievements(),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = results[0] as UserProfile;
        _achievements = results[1] as List<UserAchievement>;
        _isLoading = false;
      });
      // Deliberately NOT awaited: this is called from RefreshIndicator's
      // onRefresh, which only finishes spinning once this Future
      // completes -- if the celebration dialog (which itself resolves
      // only once the user dismisses it) were awaited here, the pull-to-
      // refresh spinner would stay stuck "in progress" for as long as the
      // dialog stayed open. The achievement list itself is already up to
      // date by this point regardless.
      unawaited(_celebrateNewlyEarned());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Не удалось загрузить профиль';
      });
    }
  }

  Future<Set<int>> _readSeenIds() async {
    final raw = await _localStorage.read(key: _seenAchievementsKey);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as List<dynamic>).map((e) => e as int).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeSeenIds(Set<int> ids) async {
    await _localStorage.write(key: _seenAchievementsKey, value: jsonEncode(ids.toList()));
  }

  /// Shows the unlock celebration for any earned achievement this device
  /// hasn't already shown it for -- e.g. one earned while the user was
  /// mid-lesson, only actually seen the next time they open Профиль.
  Future<void> _celebrateNewlyEarned() async {
    final seen = await _readSeenIds();
    final newlyEarned = _achievements.where((a) => a.earned && !seen.contains(a.id)).toList();
    if (newlyEarned.isEmpty) return;

    await _writeSeenIds({...seen, ...newlyEarned.map((a) => a.id)});
    for (final achievement in newlyEarned) {
      if (!mounted) return;
      await _showUnlockDialog(achievement);
    }
  }

  Future<void> _showUnlockDialog(UserAchievement achievement) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Достижение получено',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, _, _) => _AchievementUnlockedDialog(achievement: achievement),
      transitionBuilder: (_, animation, _, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.elasticOut),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
    );
  }

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final XFile? picked;
    try {
      picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1024, imageQuality: 85);
    } catch (_) {
      _showSnack('Не удалось открыть галерею');
      return;
    }
    if (picked == null) return;

    setState(() => _isUpdatingAvatar = true);
    try {
      final bytes = await picked.readAsBytes();
      final profile = await ApiClient.instance.uploadMyAvatar(bytes, picked.name);
      if (!mounted) return;
      setState(() => _profile = profile);
    } on ApiException catch (e) {
      _showSnack(e.message);
    } catch (_) {
      _showSnack('Не удалось загрузить фото');
    } finally {
      if (mounted) setState(() => _isUpdatingAvatar = false);
    }
  }

  Future<void> _removeAvatar() async {
    setState(() => _isUpdatingAvatar = true);
    try {
      final profile = await ApiClient.instance.deleteMyAvatar();
      if (!mounted) return;
      setState(() => _profile = profile);
    } catch (_) {
      _showSnack('Не удалось удалить фото');
    } finally {
      if (mounted) setState(() => _isUpdatingAvatar = false);
    }
  }

  void _showSnack(String text) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  void _showAvatarOptions() {
    final hasAvatar = _profile?.avatarUrl != null;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Выбрать фотографию'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickAndUploadAvatar();
              },
            ),
            if (hasAvatar)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Удалить фотографию', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _removeAvatar();
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return ListView(children: const [SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))]);
    }
    if (_loadError != null) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_loadError!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: _load, child: const Text('Повторить')),
              ],
            ),
          ),
        ],
      );
    }

    final profile = _profile!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        Center(
          child: Column(
            children: [
              GestureDetector(
                onTap: _isUpdatingAvatar ? null : _showAvatarOptions,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Opacity(
                      opacity: _isUpdatingAvatar ? 0.5 : 1,
                      child: UserAvatar(avatarUrl: profile.avatarUrl, login: profile.login, size: 96),
                    ),
                    if (_isUpdatingAvatar)
                      const Positioned.fill(child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                    else
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Theme.of(context).colorScheme.primary,
                          border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2),
                        ),
                        child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(profile.login, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('ID: ${profile.id}', style: const TextStyle(fontSize: 13, color: Colors.black45)),
            ],
          ),
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            const Text('Достижения', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            if (_achievements.isNotEmpty)
              Text(
                '${_achievements.where((a) => a.earned).length} / ${_achievements.length}',
                style: const TextStyle(fontSize: 13, color: Colors.black45, fontWeight: FontWeight.w600),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_achievements.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Пока нет доступных достижений', style: TextStyle(color: Colors.black54)),
          )
        else
          for (final achievement in _achievements) _AchievementTile(achievement: achievement),
      ],
    );
  }
}

class _AchievementTile extends StatelessWidget {
  final UserAchievement achievement;
  const _AchievementTile({required this.achievement});

  @override
  Widget build(BuildContext context) {
    final earned = achievement.earned;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: earned ? Colors.amber.shade50 : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: earned ? Colors.amber.shade300 : Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Opacity(
            opacity: earned ? 1 : 0.35,
            child: Text(achievementEmoji(achievement.icon), style: const TextStyle(fontSize: 28)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  achievement.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: earned ? Colors.black87 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  achievement.description,
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
                if (!earned) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: achievement.conditionValue == 0
                          ? 0
                          : (achievement.currentValue / achievement.conditionValue).clamp(0.0, 1.0),
                      minHeight: 5,
                      backgroundColor: Colors.grey.shade200,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${achievement.currentValue} / ${achievement.conditionValue}',
                    style: const TextStyle(fontSize: 11, color: Colors.black45),
                  ),
                ],
              ],
            ),
          ),
          if (earned)
            Icon(Icons.check_circle, color: Colors.amber.shade700, size: 22)
          else
            Icon(Icons.lock_outline, color: Colors.grey.shade400, size: 20),
        ],
      ),
    );
  }
}

class _AchievementUnlockedDialog extends StatelessWidget {
  final UserAchievement achievement;
  const _AchievementUnlockedDialog({required this.achievement});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 32, offset: const Offset(0, 12))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(colors: [Color(0xFFFFD54F), Color(0xFFFFA000)]),
                  boxShadow: [BoxShadow(color: Colors.amber.withValues(alpha: 0.5), blurRadius: 28, spreadRadius: 2)],
                ),
                child: Center(child: Text(achievementEmoji(achievement.icon), style: const TextStyle(fontSize: 44))),
              ),
              const SizedBox(height: 18),
              const Text('Достижение получено!', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black45, letterSpacing: 0.5)),
              const SizedBox(height: 6),
              Text(achievement.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(achievement.description, style: const TextStyle(fontSize: 14, color: Colors.black54), textAlign: TextAlign.center),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Отлично!'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
