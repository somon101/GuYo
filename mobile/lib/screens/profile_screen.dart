import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../api/api_client.dart';
import '../models/user_profile.dart';
import '../models/user_rating.dart';
import '../widgets/rank_icon.dart';
import '../widgets/user_avatar.dart';

const List<String> _russianMonthsGenitive = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];

/// "Получено 21 сентября 2026" -- from `earnedAt`, which the backend always
/// sends as a server timestamp (see UserAchievement.earned_at), never the
/// phone's own clock.
String _formatEarnedDate(DateTime date) {
  final local = date.toLocal();
  return '${local.day} ${_russianMonthsGenitive[local.month - 1]} ${local.year}';
}

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
  UserRating? _rating;
  bool _isUpdatingAvatar = false;
  // The just-picked photo's raw bytes, shown immediately via Image.memory
  // while the upload is still in flight -- the user sees THEIR photo the
  // instant they pick it, never a blank/waiting circle for however long
  // the network takes. Cleared on both success (the real server URL takes
  // over, now itself cached to disk by CachedNetworkImage) and failure
  // (reverts to whatever avatar was showing before this pick).
  Uint8List? _pendingAvatarBytes;

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
        ApiClient.instance.fetchMyRating(),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = results[0] as UserProfile;
        _achievements = results[1] as List<UserAchievement>;
        _rating = results[2] as UserRating;
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
    } catch (e) {
      _showSnack('Не удалось открыть галерею: $e');
      return;
    }
    if (picked == null) {
      // Distinguishes a real "nothing picked" from every other silent
      // failure mode below -- some OEM gallery pickers return null here
      // even after the user visibly picks something (a cancelled/failed
      // crop step, for instance), which otherwise looks identical to
      // every other kind of silent no-op.
      _showSnack('Файл не выбран');
      return;
    }

    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    // Optimistic preview -- set BEFORE the network call even starts, so
    // there is no window at all where the screen shows nothing new.
    setState(() {
      _pendingAvatarBytes = bytes;
      _isUpdatingAvatar = true;
    });
    try {
      final profile = await ApiClient.instance.uploadMyAvatar(bytes, picked.name, mimeType: picked.mimeType);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _pendingAvatarBytes = null;
      });
      // Explicit success feedback -- previously silent on success, so a
      // real upload that landed fine on the backend but whose new photo
      // failed to actually RENDER (bad network, a stale cached widget)
      // looked identical to "nothing happened at all".
      _showSnack('Фото обновлено');
    } on ApiException catch (e) {
      if (mounted) setState(() => _pendingAvatarBytes = null);
      _showSnack(e.message);
    } catch (e) {
      // Includes the raw exception text (not just a generic message) --
      // this upload path has silently failed on some real devices before
      // with no visible cause, so surfacing exactly what threw is worth
      // more here than a clean but uninformative message.
      if (mounted) setState(() => _pendingAvatarBytes = null);
      _showSnack('Не удалось загрузить фото: $e');
    } finally {
      if (mounted) setState(() => _isUpdatingAvatar = false);
    }
  }

  Future<void> _removeAvatar() async {
    setState(() {
      _isUpdatingAvatar = true;
      _pendingAvatarBytes = null;
    });
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
                      child: _pendingAvatarBytes != null
                          ? ClipOval(
                              child: Image.memory(
                                _pendingAvatarBytes!,
                                width: 96,
                                height: 96,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                              ),
                            )
                          : UserAvatar(avatarUrl: profile.avatarUrl, login: profile.login, size: 96),
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
              const SizedBox(height: 10),
              _StreakBadge(days: profile.currentStreakDays),
            ],
          ),
        ),
        const SizedBox(height: 28),
        if (_rating != null) _RatingSection(rating: _rating!),
        const SizedBox(height: 28),
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

/// "N дней подряд" -- `days` is computed entirely server-side
/// (backend/app/achievements/conditions.py's streak_days_count, the SAME
/// number the "Активность" achievement condition_type uses), reusing
/// UserActivityDay as its one source of truth. Never a locally-tracked
/// counter: a fresh login on another device shows this exact same value.
class _StreakBadge extends StatelessWidget {
  final int days;
  const _StreakBadge({required this.days});

  String _dayWord(int n) {
    final mod100 = n % 100;
    if (mod100 >= 11 && mod100 <= 14) return 'дней';
    switch (n % 10) {
      case 1:
        return 'день';
      case 2:
      case 3:
      case 4:
        return 'дня';
      default:
        return 'дней';
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = days > 0;
    final color = active ? Colors.orange.shade700 : Colors.black38;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? Colors.orange.withValues(alpha: 0.1) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(active ? Icons.local_fire_department_rounded : Icons.local_fire_department_outlined, color: color, size: 16),
          const SizedBox(width: 5),
          Text(
            active ? '$days ${_dayWord(days)} подряд' : 'Начните серию сегодня',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

/// "Рейтинг" -- entirely separate from achievements below: its own
/// backend system (see backend/app/rating/), its own visual block. Shows
/// the current rank/points/progress-to-next-rank, and (compactly) past
/// seasons' frozen results. Everything here is exactly what the backend
/// sent; this widget never computes a rank or a progress fraction itself
/// beyond simple arithmetic on numbers the backend already gave it.
class _RatingSection extends StatelessWidget {
  final UserRating rating;
  const _RatingSection({required this.rating});

  @override
  Widget build(BuildContext context) {
    final rank = rating.rank;
    final nextRank = rating.nextRank;
    final color = rank != null ? parseHexColor(rank.color) : Colors.grey;

    double? progress;
    if (rank != null && nextRank != null) {
      final span = nextRank.minPoints - rank.minPoints;
      if (span > 0) {
        progress = ((rating.totalPoints - rank.minPoints) / span).clamp(0.0, 1.0);
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Рейтинг', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (rating.season != null)
                Text(
                  rating.season!.name,
                  style: const TextStyle(fontSize: 12, color: Colors.black45, fontWeight: FontWeight.w600),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              RankIcon(rank: rank, color: color, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rank?.name ?? 'Без ранга',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color),
                    ),
                    const SizedBox(height: 2),
                    Text('${rating.totalPoints} очков', style: const TextStyle(fontSize: 13, color: Colors.black54)),
                  ],
                ),
              ),
            ],
          ),
          if (progress != null && nextRank != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'До «${nextRank.name}»: ${rating.pointsToNextRank} очков',
              style: const TextStyle(fontSize: 11, color: Colors.black45),
            ),
          ],
          if (rating.history.isNotEmpty) ...[
            const SizedBox(height: 14),
            Divider(height: 1, color: color.withValues(alpha: 0.15)),
            const SizedBox(height: 10),
            const Text(
              'История сезонов',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black45),
            ),
            const SizedBox(height: 6),
            for (final entry in rating.history) _SeasonHistoryRow(entry: entry),
          ],
        ],
      ),
    );
  }
}

class _SeasonHistoryRow extends StatelessWidget {
  final SeasonHistoryEntry entry;
  const _SeasonHistoryRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final rank = entry.rank;
    final color = rank != null ? parseHexColor(rank.color) : Colors.black45;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(entry.seasonName, style: const TextStyle(fontSize: 12, color: Colors.black87)),
          ),
          if (rank != null) ...[
            Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
            const SizedBox(width: 5),
            Text(rank.name, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
          ],
          Text('${entry.points}', style: const TextStyle(fontSize: 12, color: Colors.black45)),
        ],
      ),
    );
  }
}

class _AchievementTile extends StatelessWidget {
  final UserAchievement achievement;
  const _AchievementTile({required this.achievement});

  @override
  Widget build(BuildContext context) {
    final earned = achievement.earned;
    final locked = achievement.isLocked;
    final color = parseHexColor(achievement.color);
    final title = locked ? 'Скрытое достижение' : achievement.title!;
    final description = locked ? 'Условие неизвестно' : achievement.description!;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: earned ? color.withValues(alpha: 0.08) : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: earned ? color.withValues(alpha: 0.4) : Colors.grey.shade300),
      ),
      child: Row(
        children: [
          _AchievementIcon(achievement: achievement, dimmed: !earned, size: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: earned ? Colors.black87 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 2),
                Text(description, style: const TextStyle(fontSize: 13, color: Colors.black54)),
                if (earned && achievement.earnedAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Получено ${_formatEarnedDate(achievement.earnedAt!)}',
                    style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
                  ),
                ],
                if (!earned && !locked) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: achievement.conditionValue == 0
                          ? 0
                          : (achievement.currentValue! / achievement.conditionValue!).clamp(0.0, 1.0),
                      minHeight: 5,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation(color),
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
            Icon(Icons.check_circle, color: color, size: 22)
          else
            Icon(Icons.lock_outline, color: Colors.grey.shade400, size: 20),
        ],
      ),
    );
  }
}


/// The achievement's own uploaded icon -- never a substitute/generic image
/// -- shown at full brightness once earned, dimmed while locked/unearned
/// (including the hidden "mystery" state, which still uses the admin's
/// real icon, just darkened, per spec). Falls back to a generic badge only
/// when no icon was ever uploaded (or it fails to load), tinted by the
/// achievement's own color.
class _AchievementIcon extends StatelessWidget {
  final UserAchievement achievement;
  final bool dimmed;
  final double size;
  const _AchievementIcon({required this.achievement, required this.dimmed, required this.size});

  @override
  Widget build(BuildContext context) {
    final color = parseHexColor(achievement.color);
    final url = achievement.iconUrl;
    Widget child;
    if (url != null && url.isNotEmpty) {
      child = ClipOval(
        child: Image.network(
          ApiClient.instance.mediaUrl(url),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _fallbackIcon(color),
        ),
      );
    } else {
      child = _fallbackIcon(color);
    }
    return Opacity(opacity: dimmed ? 0.35 : 1, child: child);
  }

  Widget _fallbackIcon(Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.15)),
      child: Icon(Icons.emoji_events_rounded, color: color, size: size * 0.55),
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
                width: 96,
                height: 96,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: parseHexColor(achievement.color).withValues(alpha: 0.15),
                  boxShadow: [BoxShadow(color: parseHexColor(achievement.color).withValues(alpha: 0.5), blurRadius: 28, spreadRadius: 2)],
                ),
                child: _AchievementIcon(achievement: achievement, dimmed: false, size: 88),
              ),
              const SizedBox(height: 18),
              const Text('Достижение получено!', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black45, letterSpacing: 0.5)),
              const SizedBox(height: 6),
              Text(achievement.title!, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(achievement.description!, style: const TextStyle(fontSize: 14, color: Colors.black54), textAlign: TextAlign.center),
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
