import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/season_pass.dart';
import '../theme/app_colors.dart';
import '../widgets/season_pass_ui.dart';
import '../widgets/user_avatar.dart';

/// «Мои награды»: the badges and titles earned in season passes. Tap one to
/// wear it (it shows next to the name and in the rating), tap again to take it off.
class CosmeticsScreen extends StatefulWidget {
  /// Shown at once with no request (used by tests and previews).
  final CosmeticCollection? initial;
  const CosmeticsScreen({super.key, this.initial});

  @override
  State<CosmeticsScreen> createState() => _CosmeticsScreenState();
}

class _CosmeticsScreenState extends State<CosmeticsScreen> {
  CosmeticCollection? _data;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _data = widget.initial;
      _loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final data = await ApiClient.instance.fetchCosmetics();
      if (mounted) setState(() => _data = data);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _wear({int? badgeId, int? titleId, int? frameId}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final data = await ApiClient.instance.equipCosmetics(badgeId: badgeId, titleId: titleId, frameId: frameId);
      if (mounted) setState(() => _data = data);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Не удалось. Проверьте интернет.'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(tr('Мои награды')), backgroundColor: Colors.transparent, scrolledUnderElevation: 0),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : data == null || (data.badges.isEmpty && data.titles.isEmpty && data.frames.isEmpty)
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  tr('Здесь будут значки и титулы из пропуска сезона'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: AppColors.secondaryText),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                if (data.badges.isNotEmpty) ...[
                  _Title(tr('Значки')),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final b in data.badges)
                        _BadgeTile(
                          badge: b,
                          worn: data.equippedBadgeId == b.id,
                          onTap: () => _wear(
                            badgeId: data.equippedBadgeId == b.id ? null : b.id,
                            titleId: data.equippedTitleId,
                            frameId: data.equippedFrameId,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                ],
                if (data.frames.isNotEmpty) ...[
                  _Title(tr('Рамки аватара')),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final f in data.frames)
                        _FrameTile(
                          frame: f,
                          worn: data.equippedFrameId == f.id,
                          onTap: () => _wear(
                            badgeId: data.equippedBadgeId,
                            titleId: data.equippedTitleId,
                            frameId: data.equippedFrameId == f.id ? null : f.id,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                ],
                if (data.titles.isNotEmpty) ...[
                  _Title(tr('Титулы')),
                  for (final t in data.titles)
                    _TitleRow(
                      title: t,
                      worn: data.equippedTitleId == t.id,
                      onTap: () => _wear(
                        badgeId: data.equippedBadgeId,
                        titleId: data.equippedTitleId == t.id ? null : t.id,
                        frameId: data.equippedFrameId,
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}

class _Title extends StatelessWidget {
  final String text;
  const _Title(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: AppColors.primaryDark)),
  );
}

class _BadgeTile extends StatelessWidget {
  final Cosmetic badge;
  final bool worn;
  final VoidCallback onTap;
  const _BadgeTile({required this.badge, required this.worn, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        width: 104,
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: worn ? AppColors.primary : AppColors.cardBorder, width: worn ? 2.5 : 1),
          boxShadow: AppShapes.cardShadow,
        ),
        child: Column(
          children: [
            BadgeGlyph(badgeKey: badge.key, size: 56),
            const SizedBox(height: 8),
            Text(
              badge.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
            ),
            if (badge.seasonName != null)
              Text(badge.seasonName!, style: TextStyle(fontSize: 11, color: AppColors.secondaryText)),
            const SizedBox(height: 4),
            Text(
              worn ? tr('Надет') : tr('Надеть'),
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: worn ? AppColors.success : AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class _FrameTile extends StatelessWidget {
  final Cosmetic frame;
  final bool worn;
  final VoidCallback onTap;
  const _FrameTile({required this.frame, required this.worn, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: ValueKey('frame-${frame.id}'),
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        width: 104,
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: worn ? AppColors.primary : AppColors.cardBorder, width: worn ? 2.5 : 1),
          boxShadow: AppShapes.cardShadow,
        ),
        child: Column(
          children: [
            UserAvatar(avatarUrl: null, login: 'G', size: 60, frame: frame.key),
            const SizedBox(height: 8),
            Text(
              frame.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
            ),
            const SizedBox(height: 4),
            Text(
              worn ? tr('Надет') : tr('Надеть'),
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: worn ? AppColors.success : AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class _TitleRow extends StatelessWidget {
  final Cosmetic title;
  final bool worn;
  final VoidCallback onTap;
  const _TitleRow({required this.title, required this.worn, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: worn ? AppColors.primary : AppColors.cardBorder, width: worn ? 2.5 : 1),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(colors: [Color(0xFF6EE7B7), Color(0xFF0E9F6E)]),
                ),
                child: const Icon(Icons.badge_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title.label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
                    if (title.seasonName != null)
                      Text(title.seasonName!, style: TextStyle(fontSize: 11.5, color: AppColors.secondaryText)),
                  ],
                ),
              ),
              Text(
                worn ? tr('Надет') : tr('Надеть'),
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: worn ? AppColors.success : AppColors.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
