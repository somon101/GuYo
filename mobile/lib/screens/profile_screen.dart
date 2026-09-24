import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../api/api_client.dart';
import '../models/dictionary.dart';
import '../models/user_profile.dart';
import '../models/user_rating.dart';
import '../theme/app_colors.dart';
import '../widgets/achievement_icon.dart';
import '../widgets/rank_icon.dart';
import '../widgets/remote_image.dart';
import '../widgets/user_avatar.dart';
import 'achievements_screen.dart';
import 'all_ranks_screen.dart';
import 'learned_words_screen.dart';
import 'profile_settings_screen.dart';

/// "Профиль": the user's own identity (avatar, login, their permanent
/// user_id), their three headline counters, their current rank, and a
/// compact strip of achievements -- all fetched from the backend, which is
/// the sole source of truth for every one of those numbers (see
/// backend/app/achievements/ and backend/app/rating/). This screen only
/// renders what it's given and uploads/removes an avatar file; nothing
/// about earning or ranking logic lives here.
///
/// Its State is public so HomeScreen's own app bar can open this screen's
/// settings sheet from the gear button it shows while this tab is active
/// (see HomeScreen's `_profileKey`) -- the sheet itself, and everything it
/// does, still belongs entirely to this screen.
class ProfileScreen extends StatefulWidget {
  /// Only used to open "Мои слова", which IS language-scoped. The profile
  /// itself still is not: nothing else here changes with the selected
  /// language, and this tab is deliberately not rebuilt when it changes.
  final GuyoDictionary dictionary;

  /// Switches the app to the "Уроки" tab. Уроки is a sibling tab rather
  /// than a route, so the profile asks the shell to switch instead of
  /// pushing a second copy of that screen -- the same way Главная's
  /// "Квест дня" already reaches it.
  final VoidCallback onOpenLessons;

  const ProfileScreen({
    super.key,
    required this.dictionary,
    required this.onOpenLessons,
  });

  @override
  State<ProfileScreen> createState() => ProfileScreenState();
}

// Persisted locally purely so the unlock celebration is shown at most once
// per achievement, even across app restarts -- earning itself is already
// fully durable on the backend regardless of this; this is only "have I
// already shown the user this specific celebration".
const _seenAchievementsKey = 'guyo_seen_achievement_ids';
final _localStorage = FlutterSecureStorage();

class ProfileScreenState extends State<ProfileScreen> {
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

  Future<UserProfile?> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final XFile? picked;
    try {
      picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1024, imageQuality: 85);
    } catch (e) {
      _showSnack('Не удалось открыть галерею: $e');
      return null;
    }
    if (picked == null) {
      // Distinguishes a real "nothing picked" from every other silent
      // failure mode below -- some OEM gallery pickers return null here
      // even after the user visibly picks something (a cancelled/failed
      // crop step, for instance), which otherwise looks identical to
      // every other kind of silent no-op.
      _showSnack('Файл не выбран');
      return null;
    }

    // picker.pickImage() backgrounds this Activity for as long as the
    // system picker is on screen -- on a low-RAM device Android can reclaim
    // enough memory meanwhile to tear down and recreate the Activity/engine
    // entirely, which disposes THIS exact State object before control ever
    // returns here. Calling setState on that already-disposed State is
    // undefined in release builds -- confirmed via a real device log as a
    // framework-internal crash ("Null check operator used on a null value"
    // inside State.setState) that aborted this whole function silently
    // before it ever reached readAsBytes(), which is exactly what looked
    // like "picks a photo, screen goes blank, nothing ever happens".
    if (!mounted) return null;
    // Set BEFORE reading any bytes, not after -- readAsBytes() opens the
    // picked content:// URI through the OS, which on a real device can
    // take a real, visible moment (or throw, see below), and previously
    // showed nothing at all -- no spinner, no feedback -- for however long
    // that took, which is exactly what looked like a frozen white screen.
    setState(() => _isUpdatingAvatar = true);
    Uint8List bytes;
    try {
      bytes = await picked.readAsBytes();
    } catch (e) {
      // This was completely unguarded before: readAsBytes() can genuinely
      // throw on Android (a revoked URI grant, the Activity having been
      // recreated under memory pressure while the gallery was open) and
      // nothing anywhere caught it, so the failure vanished into an
      // unhandled Future error -- no snackbar, no state change, the exact
      // "picks a photo, then nothing happens at all" this was chasing.
      if (mounted) setState(() => _isUpdatingAvatar = false);
      _showSnack('Не удалось прочитать фото: $e');
      return null;
    }
    if (!mounted) return null;
    // Optimistic preview -- set BEFORE the network call even starts, so
    // there is no window at all where the screen shows nothing new.
    setState(() => _pendingAvatarBytes = bytes);
    try {
      final profile = await ApiClient.instance.uploadMyAvatar(bytes, picked.name, mimeType: picked.mimeType);
      if (!mounted) return null;
      setState(() {
        _profile = profile;
        _pendingAvatarBytes = null;
      });
      // Explicit success feedback -- previously silent on success, so a
      // real upload that landed fine on the backend but whose new photo
      // failed to actually RENDER (bad network, a stale cached widget)
      // looked identical to "nothing happened at all".
      _showSnack('Фото обновлено');
      return profile;
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
    return null;
  }

  Future<UserProfile?> _removeAvatar() async {
    setState(() {
      _isUpdatingAvatar = true;
      _pendingAvatarBytes = null;
    });
    try {
      final profile = await ApiClient.instance.deleteMyAvatar();
      if (!mounted) return null;
      setState(() => _profile = profile);
      return profile;
    } catch (_) {
      _showSnack('Не удалось удалить фото');
    } finally {
      if (mounted) setState(() => _isUpdatingAvatar = false);
    }
    return null;
  }

  void _showSnack(String text) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  /// Opens the app's existing "Мои слова" screen -- the same one, with all
  /// of its own search, filters and categories. This is a way in, not a
  /// second copy of it.
  Future<void> _openLearnedWords() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LearnedWordsScreen(dictionary: widget.dictionary)),
    );
  }

  Future<void> _openAchievements() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AchievementsScreen(achievements: _achievements)),
    );
  }

  Future<void> _openRanks() async {
    final rating = _rating;
    if (rating == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AllRanksScreen(rating: rating)),
    );
  }

  /// The gear button opens the "Настройки" screen -- login, photo, name,
  /// surname and email, each editable there. It is a screen rather than
  /// the old photo-only sheet because changing the photo is no longer the
  /// only thing settings does.
  ///
  /// The avatar actions are handed over rather than reimplemented: that
  /// path carries real-device fixes worth keeping in exactly one place
  /// (see _pickAndUploadAvatar).
  void openSettings() {
    final profile = _profile;
    if (profile == null) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => ProfileSettingsScreen(
              profile: profile,
              onPickPhoto: _pickAndUploadAvatar,
              onRemovePhoto: _removeAvatar,
            ),
          ),
        )
        // Whatever was saved came back from the backend already; reloading
        // keeps this screen showing exactly what the server now holds.
        .then((_) => _load());
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
    final rating = _rating;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        _ProfileHeader(
          profile: profile,
          pendingAvatarBytes: _pendingAvatarBytes,
          isUpdatingAvatar: _isUpdatingAvatar,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.local_fire_department_rounded,
                iconColor: const Color(0xFFFF7A29),
                iconBackground: const Color(0xFFFFF0E6),
                label: 'Серий',
                value: '${profile.currentStreakDays} ${_dayWord(profile.currentStreakDays)}',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                icon: Icons.menu_book_rounded,
                iconColor: AppColors.primary,
                iconBackground: const Color(0xFFEDEEFC),
                label: 'Уроки',
                // Still the backend's own completed-lessons count -- the
                // card just leads to the lesson chain now.
                value: '${profile.lessonsCompleted}',
                onTap: widget.onOpenLessons,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                icon: Icons.star_rounded,
                iconColor: AppColors.primary,
                iconBackground: const Color(0xFFEDEEFC),
                label: 'Мои слова',
                value: '${profile.wordsLearned}',
                // Still the same counter it always was -- it just leads
                // somewhere now.
                onTap: _openLearnedWords,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (rating != null) _RankCard(rating: rating, onTap: _openRanks),
        const SizedBox(height: 16),
        _AchievementsCard(achievements: _achievements, onTap: _openAchievements),
      ],
    );
  }
}

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

/// Avatar + name + permanent id, with the decorative QR badge on the right.
/// The avatar itself is NOT tappable any more -- changing the photo goes
/// through the gear's settings sheet only (see ProfileScreenState.
/// openSettings), which is why the old camera overlay is gone too.
class _ProfileHeader extends StatelessWidget {
  final UserProfile profile;
  final Uint8List? pendingAvatarBytes;
  final bool isUpdatingAvatar;

  const _ProfileHeader({
    required this.profile,
    required this.pendingAvatarBytes,
    required this.isUpdatingAvatar,
  });

  /// There is only something to enlarge when the user actually has a
  /// photo -- either one already stored, or one they just picked that is
  /// still uploading. With neither, the circle holds a generated letter,
  /// and blowing that up full screen would be a tap leading nowhere worth
  /// going, so the avatar simply isn't tappable then.
  bool get _hasPhoto =>
      pendingAvatarBytes != null || (profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty);

  void _openViewer(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        // Over the profile rather than instead of it: the screen stays
        // behind the dimmed backdrop, so closing is plainly "back to
        // where I was".
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black.withValues(alpha: 0.82),
        pageBuilder: (_, _, _) => _AvatarViewer(
          avatarUrl: profile.avatarUrl,
          pendingBytes: pendingAvatarBytes,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const size = 88.0;
    final cacheSize = (size * MediaQuery.devicePixelRatioOf(context)).round();

    final avatar = Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: AppColors.primary.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: isUpdatingAvatar ? 0.5 : 1,
            child: pendingAvatarBytes != null
                ? ClipOval(
                    child: Image.memory(
                      pendingAvatarBytes!,
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      // Bounds the decode to roughly this circle's own
                      // on-screen size -- without it a picked photo whose
                      // compression the OS skipped gets decoded at full
                      // resolution just to draw this circle. ONE axis
                      // only: giving both squashes a portrait photo into a
                      // square before the crop even runs (see
                      // widgets/remote_image.dart).
                      cacheWidth: cacheSize,
                    ),
                  )
                : UserAvatar(avatarUrl: profile.avatarUrl, login: profile.login, size: size),
          ),
          if (isUpdatingAvatar) const CircularProgressIndicator(strokeWidth: 2),
        ],
      ),
    );

    return Row(
      children: [
        // Tapping shows the photo full size. Changing it still goes
        // through the gear's settings sheet only -- this is a viewer, not
        // a second way to upload.
        if (_hasPhoto)
          Semantics(
            button: true,
            label: 'Открыть фото профиля',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openViewer(context),
              child: avatar,
            ),
          )
        else
          avatar,
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                profile.login,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              // The 9-digit account number -- `id` is internal and never
              // shown.
              Text(
                'ID: ${profile.publicId}',
                style: const TextStyle(fontSize: 14, color: AppColors.secondaryText),
              ),
            ],
          ),
        ),
        // Decorative only for now, by design -- there is no QR feature in
        // the app yet, so this deliberately isn't tappable rather than
        // offering a button that does nothing.
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFEDEFF7)),
          ),
          child: const Icon(Icons.qr_code_rounded, color: AppColors.primary, size: 22),
        ),
      ],
    );
  }
}

/// The profile photo at full size, over the profile screen.
///
/// Shows the very same photo the circle above does -- the one already
/// stored by the existing avatar system, or the one being uploaded right
/// now. It only displays; nothing here picks, uploads or stores anything.
///
/// BoxFit.contain, unlike the circle's crop: at full size the point is to
/// see the whole photo as it really is, so it is letterboxed rather than
/// cropped or stretched.
class _AvatarViewer extends StatelessWidget {
  final String? avatarUrl;
  final Uint8List? pendingBytes;

  const _AvatarViewer({required this.avatarUrl, required this.pendingBytes});

  @override
  Widget build(BuildContext context) {
    final bytes = pendingBytes;
    final url = avatarUrl;

    // Keyed so a test can tell this apart from the small circle behind it
    // and from the rank/achievement artwork on the same screen -- the same
    // convention the exercise screens already use for their own hooks.
    const photoKey = ValueKey('profile-photo-full');
    final Widget photo = bytes != null
        ? Image.memory(bytes, key: photoKey, fit: BoxFit.contain, gaplessPlayback: true)
        : RemoteImage(
            key: photoKey,
            url: url ?? '',
            fit: BoxFit.contain,
            fallbackBuilder: () => const Icon(Icons.person_rounded, size: 96, color: Colors.white54),
          );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        // Anywhere outside the photo closes it, the way a lightbox does.
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).maybePop(),
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: photo,
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  tooltip: 'Закрыть',
                  icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String label;
  final String value;

  /// Set only on a card that leads somewhere; the plain counters stay
  /// plain counters.
  final VoidCallback? onTap;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: _content(),
      ),
    );
  }

  Widget _content() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEDEFF7)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: iconBackground, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 17),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Scaled down rather than clipped: three of these share
                // one row, so a longer label must shrink to fit instead of
                // losing its last letters.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    style: const TextStyle(fontSize: 11, color: AppColors.secondaryText, fontWeight: FontWeight.w600),
                    maxLines: 1,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The current rank, its real position within that same rank, the points,
/// and the climb to the next one -- every number straight from
/// GET /users/me/rating, none recomputed here. Tapping anywhere opens the
/// full ladder ("Все уровни"), which the chevron stands for.
class _RankCard extends StatelessWidget {
  final UserRating rating;
  final VoidCallback onTap;
  const _RankCard({required this.rating, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final rank = rating.rank;
    final nextRank = rating.nextRank;
    final color = rank != null ? parseHexColor(rank.color) : AppColors.primary;

    double? progress;
    if (rank != null && nextRank != null) {
      final span = nextRank.minPoints - rank.minPoints;
      if (span > 0) {
        progress = ((rating.totalPoints - rank.minPoints) / span).clamp(0.0, 1.0);
      }
    }

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFEDEFF7)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.035), blurRadius: 14, offset: const Offset(0, 5)),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  RankIcon(rank: rank, color: color, size: 64),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rank?.name ?? 'Без ранга',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _positionLabel(rating),
                          style: const TextStyle(fontSize: 13, color: AppColors.secondaryText),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.workspace_premium_rounded, size: 16, color: color),
                            const SizedBox(width: 5),
                            Text(
                              '${rating.totalPoints} очков',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Color(0xFFB9BEDA), size: 22),
                ],
              ),
              if (progress != null && nextRank != null) ...[
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 7,
                    backgroundColor: const Color(0xFFEDEFF7),
                    valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Text(
                      'До следующего уровня',
                      style: TextStyle(fontSize: 12, color: AppColors.secondaryText),
                    ),
                    const Spacer(),
                    Text(
                      '${rating.totalPoints} / ${nextRank.minPoints}',
                      style: const TextStyle(fontSize: 12, color: AppColors.secondaryText, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _positionLabel(UserRating rating) {
    final rank = rating.rank;
    final position = rating.rankPosition;
    if (rank == null) return 'Ранг пока не присвоен';
    if (position == null) return rank.name;
    return '$position место • ${rank.name}';
  }
}

/// A compact strip of achievement icons plus the earned/total count --
/// the full list lives on its own screen now (see AchievementsScreen),
/// which the chevron and the count both lead to.
class _AchievementsCard extends StatelessWidget {
  final List<UserAchievement> achievements;
  final VoidCallback onTap;
  const _AchievementsCard({required this.achievements, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final earnedCount = achievements.where((a) => a.earned).length;
    // Earned ones first so the strip always shows what the user actually
    // has, even when the full list is long -- the rest keep the backend's
    // own order behind them.
    final ordered = [
      ...achievements.where((a) => a.earned),
      ...achievements.where((a) => !a.earned),
    ];
    final shown = ordered.take(6).toList();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: achievements.isEmpty ? null : onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFEDEFF7)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.035), blurRadius: 14, offset: const Offset(0, 5)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Достижения',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                  ),
                  const Spacer(),
                  if (achievements.isNotEmpty)
                    Text(
                      '$earnedCount / ${achievements.length}',
                      style: const TextStyle(fontSize: 13, color: AppColors.secondaryText, fontWeight: FontWeight.w700),
                    ),
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_right, color: Color(0xFFB9BEDA), size: 22),
                ],
              ),
              if (achievements.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text('Пока нет доступных достижений', style: TextStyle(color: AppColors.secondaryText)),
                )
              else ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    for (final achievement in shown) ...[
                      AchievementIcon(achievement: achievement, dimmed: !achievement.earned, size: 44),
                      if (achievement != shown.last) const Spacer(),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
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
                width: 96,
                height: 96,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: parseHexColor(achievement.color).withValues(alpha: 0.15),
                  boxShadow: [BoxShadow(color: parseHexColor(achievement.color).withValues(alpha: 0.5), blurRadius: 28, spreadRadius: 2)],
                ),
                child: AchievementIcon(achievement: achievement, dimmed: false, size: 88),
              ),
              const SizedBox(height: 18),
              const Text('Достижение получено!', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.secondaryText, letterSpacing: 0.5)),
              const SizedBox(height: 6),
              Text(achievement.title!, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primaryDark), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(achievement.description!, style: const TextStyle(fontSize: 14, color: AppColors.secondaryText), textAlign: TextAlign.center),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
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
