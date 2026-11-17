import 'dart:math' as math;
import 'dart:ui';

import 'avatar_models.dart';

/// The part's rectangle on the canvas: its width comes from the saved place, the height keeps the picture's proportions.
Rect partRect(AvatarPart part, AvatarPlace p) {
  final h = part.w <= 0 ? p.w : part.h * p.w / part.w;
  final top = p.pivot == 'top' ? p.y : (p.pivot == 'bottom' ? p.y - h : p.y - h / 2);
  return Rect.fromLTWH(p.x - p.w / 2, top, p.w, h);
}

/// The square of the canvas that becomes the avatar picture.
Rect avatarFrame(AvatarCatalog c) => Rect.fromCenter(center: Offset(c.frameX, c.frameY), width: c.frameSize, height: c.frameSize);

/// The slots every avatar has: face, hair and clothes. Everything else (glasses, hats, hands...) is an extra
/// the person may leave off.
const requiredSlots = {'face', 'hair', 'cloth'};
bool isOptionalSlot(String slotId) => !requiredSlots.contains(slotId);

/// When the person picks a gender, a random SET of that gender is put together at once: the parts of one set go
/// well together (hair, face and clothes of the same look). A slot the set has nothing for gets a random part of
/// that slot; the background is random too. The person then changes whatever they like.
AvatarChoice randomChoice(AvatarCatalog c, String gender, math.Random rnd) {
  final slots = c.slotsFor(gender);
  final sets = <String>{for (final p in c.parts) if (p.fits(gender) && p.setId.isNotEmpty) p.setId}.toList();
  final setId = sets.isEmpty ? null : sets[rnd.nextInt(sets.length)];
  final picked = <String, String>{};
  for (final s in slots) {
    // an extra (glasses...) is put on for about half of the random avatars, the rest go without
    if (isOptionalSlot(s.id) && rnd.nextBool()) continue;
    final all = c.partsFor(s.id, gender);
    final inSet = setId == null ? <AvatarPart>[] : [for (final p in all) if (p.setId == setId) p];
    final pool = inSet.isNotEmpty ? inSet : all;
    picked[s.id] = pool[rnd.nextInt(pool.length)].id;
  }
  final bg = c.backgrounds.isEmpty ? null : c.backgrounds[rnd.nextInt(c.backgrounds.length)].id;
  return AvatarChoice(gender: gender, slots: picked, bg: bg);
}

/// What the editor has to download for this choice, first: the parts and background currently shown.
List<String> urlsOf(AvatarCatalog c, AvatarChoice choice) => [
      for (final e in choice.slots.entries)
        if (c.part(e.value) != null) c.part(e.value)!.url,
      if (c.background(choice.bg)?.url != null) c.background(choice.bg)!.url!,
    ];
