import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../avatar/avatar_logic.dart';
import '../avatar/avatar_models.dart';
import '../avatar/avatar_painter.dart';
import '../avatar/avatar_store.dart';
import '../l10n/l10n.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import '../widgets/skeleton.dart';

/// "Создание аватара": instead of uploading a photo the person builds an avatar from parts that come from the
/// server (see lib/avatar). They pick a gender, a random set of that gender is put together at once, and then
/// they change hair, face, clothes... step by step and finally the background. Nothing is placed by hand: every
/// part sits where the Studio saved it.
///
/// The editor opens at once from the copy kept on the phone; pictures are fetched as they are needed, and white
/// squares stand in their places until they arrive. "Готово" draws the picture, sends it with the choice to the
/// server and keeps it on the phone too, so the avatar shows everywhere (even offline) like any photo.
class AvatarEditorScreen extends StatefulWidget {
  final UserProfile profile;

  /// Fixed in tests so the "random" set is predictable.
  final math.Random? random;
  const AvatarEditorScreen({super.key, required this.profile, this.random});

  @override
  State<AvatarEditorScreen> createState() => _AvatarEditorScreenState();
}

String slotTitle(AvatarSlot s) {
  switch (s.id) {
    case 'hair':
      return tr('Волосы');
    case 'face':
      return tr('Лицо');
    case 'cloth':
      return tr('Одежда');
    case 'glasses':
      return tr('Очки');
    case 'neck':
      return tr('Шея');
    case 'handL':
      return tr('Левая рука');
    case 'handR':
      return tr('Правая рука');
    default:
      return s.name;
  }
}

class _AvatarEditorScreenState extends State<AvatarEditorScreen> {
  final _store = AvatarStore.instance;
  late final math.Random _rnd = widget.random ?? math.Random();
  AvatarCatalog? _catalog;
  AvatarChoice? _choice;
  bool _failed = false;
  bool _saving = false;
  int _step = 0; // 0 gender, then one step per slot, then the background
  int _revision = 0;
  final Set<String> _requested = {};

  AvatarStoreAccess get _images => AvatarStoreAccess(_store);

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  Future<void> _boot() async {
    // 1. what the phone already has: opens at once
    final cached = await _store.cached();
    if (cached != null && mounted) _useCatalog(cached, first: true);
    // 2. ask the server quietly; take the new catalog only if it changed
    try {
      final fresh = await _store.refresh();
      if (fresh != null && mounted && !identical(fresh, _catalog)) _useCatalog(fresh, first: _catalog == null);
    } catch (_) {
      if (mounted && _catalog == null) setState(() => _failed = true);
    }
  }

  void _useCatalog(AvatarCatalog c, {required bool first}) {
    setState(() {
      _catalog = c;
      _failed = false;
      final mine = AvatarChoice.fromLook(widget.profile.avatarLook);
      if (_choice == null && mine != null && first) {
        // editing the avatar made before: its choice, minus parts that no longer exist
        _choice = AvatarChoice(
          gender: mine.gender,
          slots: {for (final e in mine.slots.entries) if (c.part(e.value) != null) e.key: e.value},
          bg: c.background(mine.bg) != null ? mine.bg : null,
        );
        _step = 1;
      } else if (_choice != null) {
        // the catalog changed under us: drop what is gone
        _choice = AvatarChoice(
          gender: _choice!.gender,
          slots: {for (final e in _choice!.slots.entries) if (c.part(e.value) != null) e.key: e.value},
          bg: c.background(_choice!.bg) != null ? _choice!.bg : null,
        );
      }
    });
    if (_choice != null) _want(urlsOf(c, _choice!));
  }

  /// Starts downloading pictures nobody asked for yet; the screen redraws as each one arrives.
  void _want(Iterable<String> urls) {
    for (final url in urls) {
      if (_images.has(url) || !_requested.add(url)) continue;
      _store.image(url).then((im) {
        if (im == null) _requested.remove(url);
        if (mounted) setState(() => _revision++);
      });
    }
  }

  void _chooseGender(String gender) {
    final c = _catalog;
    if (c == null) return;
    final choice = randomChoice(c, gender, _rnd);
    setState(() {
      _choice = choice;
      _step = 1;
    });
    _want(urlsOf(c, choice));
  }

  void _dice() {
    final c = _catalog, cur = _choice;
    if (c == null || cur == null) return;
    final choice = randomChoice(c, cur.gender, _rnd);
    setState(() => _choice = choice);
    _want(urlsOf(c, choice));
  }

  List<AvatarSlot> get _slots => _catalog == null || _choice == null ? const [] : _catalog!.slotsFor(_choice!.gender);
  bool get _hasBg => _catalog?.backgrounds.isNotEmpty ?? false;
  int get _lastStep => _slots.length + (_hasBg ? 1 : 0);

  List<String> get _stepNames => [tr('Пол'), ..._slots.map(slotTitle), if (_hasBg) tr('Фон')];

  Future<void> _save() async {
    final c = _catalog, choice = _choice;
    if (c == null || choice == null || _saving) return;
    setState(() => _saving = true);
    try {
      // everything shown must be on the phone before the picture is drawn
      await Future.wait([for (final url in urlsOf(c, choice)) _store.image(url)]);
      final png = await renderAvatarPng(c, choice, _store.images);
      final url = await ApiClient.instance.saveMyAvatar(choice.toJson(), png);
      await _store.replaceMyAvatar(oldUrl: widget.profile.avatarUrl, newUrl: url, png: png);
      final profile = await ApiClient.instance.fetchMyProfile();
      if (!mounted) return;
      Navigator.of(context).pop(profile);
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack(tr('Не удалось сохранить аватар: {0}', [e]));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final c = _catalog;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(tr('Создание аватара'), style: TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w800)),
        iconTheme: IconThemeData(color: AppColors.primary),
      ),
      body: SafeArea(child: c == null ? _loading() : _body(c)),
    );
  }

  /// Before the catalog is here: the editor's shape is already on screen, white squares where pictures will be.
  Widget _loading() {
    return Column(
      children: [
        if (_failed) ...[
          const SizedBox(height: 24),
          Text(tr('Не удалось загрузить детали. Проверьте интернет и попробуйте снова.'), textAlign: TextAlign.center, style: TextStyle(color: AppColors.secondaryText)),
          const SizedBox(height: 12),
          FilledButton(onPressed: () { setState(() => _failed = false); unawaited(_boot()); }, child: Text(tr('Повторить'))),
        ] else ...[
          const SizedBox(height: 16),
          Center(child: _squareSkeleton(190, circle: true)),
          const SizedBox(height: 16),
          Expanded(child: _skeletonGrid()),
        ],
      ],
    );
  }

  Widget _squareSkeleton(double size, {bool circle = false}) {
    return SkeletonPulse(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: circle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: circle ? null : BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder, width: 2),
        ),
      ),
    );
  }

  Widget _skeletonGrid() => GridView.count(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [for (var i = 0; i < 12; i++) _squareSkeleton(60)],
      );

  Widget _body(AvatarCatalog c) {
    if (c.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(tr('Деталей для аватара пока нет'), style: TextStyle(color: AppColors.secondaryText))));
    }
    final choice = _choice;
    return Column(
      children: [
        _chips(),
        if (choice != null && _step > 0) _preview(c, choice),
        Expanded(child: _step == 0 || choice == null ? _genderStep() : _pickStep(c, choice)),
        if (choice != null && _step > 0) _bottom(),
      ],
    );
  }

  Widget _chips() {
    final names = _stepNames;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        itemCount: _choice == null ? 1 : names.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final on = i == _step, done = i < _step;
          return GestureDetector(
            onTap: _choice == null ? null : () => setState(() => _step = i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? AppColors.primary : (done ? AppColors.successLight : AppColors.violetSurface),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(names[i], style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: on ? Colors.white : (done ? AppColors.success : AppColors.primary))),
            ),
          );
        },
      ),
    );
  }

  Widget _preview(AvatarCatalog c, AvatarChoice choice) {
    const size = 170.0;
    final ready = urlsOf(c, choice).any(_images.has);
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: SizedBox(
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(c.frameShape == 'circle' ? size : 36),
              child: SizedBox(
                width: size,
                height: size,
                child: Stack(children: [
                  CustomPaint(size: const Size(size, size), painter: AvatarPainter(c, choice, _store.images, _revision)),
                  if (!ready) Positioned.fill(child: _squareSkeleton(size, circle: c.frameShape == 'circle')),
                ]),
              ),
            ),
            Positioned(
              right: 24,
              top: 6,
              child: Tooltip(
                message: tr('Случайный набор'),
                child: Material(
                  color: AppColors.surface,
                  shape: CircleBorder(side: BorderSide(color: AppColors.cardBorder, width: 2)),
                  child: InkWell(customBorder: const CircleBorder(), onTap: _dice, child: Padding(padding: const EdgeInsets.all(10), child: Icon(Icons.casino_rounded, color: AppColors.primary, size: 24))),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _genderStep() {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Text(tr('Кто вы?'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: _genderCard('male', tr('Парень'), 'assets/icons/avatar_boy.png')),
            const SizedBox(width: 12),
            Expanded(child: _genderCard('female', tr('Девушка'), 'assets/icons/avatar_girl.png')),
          ]),
        ],
      ),
    );
  }

  Widget _genderCard(String gender, String label, String asset) {
    final ok = _catalog?.slotsFor(gender).isNotEmpty ?? false;
    return Opacity(
      opacity: ok ? 1 : 0.4,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: ok ? () => _chooseGender(gender) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 28),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.cardBorder, width: 2)),
          child: Column(children: [
            Image.asset(asset, height: 104, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
            const SizedBox(height: 10),
            Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
          ]),
        ),
      ),
    );
  }

  Widget _pickStep(AvatarCatalog c, AvatarChoice choice) {
    final slots = _slots;
    final onBg = _hasBg && _step == slots.length + 1;
    if (onBg) {
      final list = c.backgrounds;
      _want([for (final b in list) if (b.url != null) b.url!]);
      return _grid(list.length, (i) {
        final b = list[i];
        return _tile(selected: choice.bg == b.id, onTap: () => setState(() => _choice = choice.withBg(b.id)), child: _bgSwatch(b));
      }, title: tr('Фон'));
    }
    if (_step - 1 >= slots.length) return const SizedBox.shrink();
    final slot = slots[_step - 1];
    final parts = c.partsFor(slot.id, choice.gender);
    // an extra (glasses...) can be left off: the first square is "none"
    final optional = isOptionalSlot(slot.id);
    final shift = optional ? 1 : 0;
    return _grid(parts.length + shift, (i) {
      if (optional && i == 0) {
        return _tile(
          selected: !choice.slots.containsKey(slot.id),
          onTap: () => setState(() => _choice = choice.withoutSlot(slot.id)),
          child: Center(child: Icon(Icons.block_rounded, key: const ValueKey('avatar-none'), size: 30, color: AppColors.secondaryText)),
        );
      }
      final p = parts[i - shift];
      _want([p.url]);
      return _tile(selected: choice.slots[slot.id] == p.id, onTap: () => setState(() => _choice = choice.withSlot(slot.id, p.id)), child: _thumb(p.url));
    }, title: '${slotTitle(slot)} · ${parts.length}');
  }

  Widget _grid(int count, Widget Function(int) item, {required String title}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 6), child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primaryDark))),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8),
            itemCount: count,
            itemBuilder: (_, i) => item(i),
          ),
        ),
      ],
    );
  }

  Widget _tile({required bool selected, required VoidCallback onTap, required Widget child}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? AppColors.primary : AppColors.cardBorder, width: selected ? 3 : 2),
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(10), child: child),
      ),
    );
  }

  Widget _thumb(String url) {
    final im = _store.images[url];
    if (im == null) return SkeletonPulse(child: Container(color: Colors.white));
    return RawImage(image: im, fit: BoxFit.contain, filterQuality: FilterQuality.medium);
  }

  Widget _bgSwatch(AvatarBackground b) {
    if (b.kind == 'img') {
      final im = b.url == null ? null : _store.images[b.url];
      return im == null ? SkeletonPulse(child: Container(color: Colors.white)) : RawImage(image: im, fit: BoxFit.cover);
    }
    Color hex(String? s) => s != null && s.startsWith('#') && s.length >= 7 ? Color(0xFF000000 | int.parse(s.substring(1, 7), radix: 16)) : Colors.grey;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: b.kind == 'solid' ? hex(b.c1) : null,
        gradient: b.kind == 'grad' ? LinearGradient(colors: [hex(b.c1), hex(b.c2)], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
      ),
    );
  }

  Widget _bottom() {
    final last = _step >= _lastStep;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: last ? AppColors.success : AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          onPressed: _saving ? null : (last ? _save : () => setState(() => _step++)),
          child: _saving
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : Text(last ? tr('Готово') : tr('Дальше'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }
}

/// A thin read-only window onto the store's loaded pictures (keeps the screen code short).
class AvatarStoreAccess {
  final AvatarStore store;
  const AvatarStoreAccess(this.store);
  bool has(String url) => store.images.containsKey(url);
}
