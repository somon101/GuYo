// PremiumStatus is what Главная's lesson counter and the Premium screen
// are drawn from; these pin how the backend's GET /premium/me is read,
// including the null-means-unlimited convention.
import 'package:flutter_test/flutter_test.dart';

import 'package:guyo_app/models/premium.dart';

void main() {
  test('a free user blocked for the day', () {
    final status = PremiumStatus.fromJson({
      'is_premium': false,
      'premium_until': null,
      'public_id': 482915306,
      'price_text': '30 сомони в месяц',
      'payment_instructions': 'Алиф: +992 ...',
      'adaptive_lessons_premium_only': true,
      'personal_quests_premium_only': false,
      'lessons': {
        'daily_limit': 3,
        'daily_used': 3,
        'weekly_limit': 10,
        'weekly_used': 5,
        'remaining': 0,
        'blocked_by': 'day',
        'resets_at': '2026-09-26T19:00:00Z',
      },
    });

    expect(status.isPremium, isFalse);
    expect(status.publicId, 482915306);
    expect(status.personalQuestsPremiumOnly, isFalse);
    expect(status.lessons.blockedBy, 'day');
    expect(status.lessons.remaining, 0);
    expect(status.lessons.isUnlimited, isFalse);
    expect(status.lessons.resetsAt!.isUtc, isFalse, reason: 'shown in the device timezone');
  });

  test('a Premium user with no limits', () {
    final status = PremiumStatus.fromJson({
      'is_premium': true,
      'premium_until': '2026-10-26T10:00:00Z',
      'public_id': 100000001,
      'price_text': '',
      'payment_instructions': '',
      'adaptive_lessons_premium_only': true,
      'personal_quests_premium_only': true,
      'lessons': {
        'daily_limit': null,
        'daily_used': 7,
        'weekly_limit': null,
        'weekly_used': 12,
        'remaining': null,
        'blocked_by': null,
        'resets_at': null,
      },
    });

    expect(status.isPremium, isTrue);
    expect(status.premiumUntil, isNotNull);
    expect(status.lessons.isUnlimited, isTrue);
    expect(status.lessons.remaining, isNull);
  });

  test('a promo activation result', () {
    final result = PromoResult.fromJson({
      'days': 90,
      'premium_until': '2026-12-25T10:00:00Z',
      'kind': 'link',
      'is_first_link': true,
      'message': '+90 дн. GuYo Premium. Premium активен до 25.12.2026.',
    });

    expect(result.days, 90);
    expect(result.kind, 'link');
    expect(result.isFirstLink, isTrue);
    expect(result.premiumUntil.isUtc, isFalse);
  });

  test('dates read as dd.mm.yyyy', () {
    expect(formatPremiumDate(DateTime(2026, 3, 5)), '05.03.2026');
  });
}
