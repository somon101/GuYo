/// Where the user stands against the lesson limits -- decided entirely by
/// the backend (app/premium/service.py). A null limit means unlimited.
class LessonQuota {
  final int? dailyLimit;
  final int dailyUsed;
  final int? weeklyLimit;
  final int weeklyUsed;

  /// The tighter of the two limits, or null when neither applies.
  final int? remaining;

  /// "day" or "week" while no lesson can be created, else null.
  final String? blockedBy;

  /// When creating becomes possible again, if it is blocked now.
  final DateTime? resetsAt;

  const LessonQuota({
    required this.dailyLimit,
    required this.dailyUsed,
    required this.weeklyLimit,
    required this.weeklyUsed,
    required this.remaining,
    required this.blockedBy,
    required this.resetsAt,
  });

  bool get isUnlimited => dailyLimit == null && weeklyLimit == null;

  factory LessonQuota.fromJson(Map<String, dynamic> json) {
    final resetsAt = json['resets_at'] as String?;
    return LessonQuota(
      dailyLimit: json['daily_limit'] as int?,
      dailyUsed: json['daily_used'] as int,
      weeklyLimit: json['weekly_limit'] as int?,
      weeklyUsed: json['weekly_used'] as int,
      remaining: json['remaining'] as int?,
      blockedBy: json['blocked_by'] as String?,
      resetsAt: resetsAt == null ? null : DateTime.parse(resetsAt).toLocal(),
    );
  }
}

/// GET /premium/me: Premium status, how to pay, and the lesson counter.
class PremiumStatus {
  final bool isPremium;
  final DateTime? premiumUntil;

  /// The admin's master switch (see backend PremiumSettings.
  /// premium_enabled's own docstring). While false, every Premium
  /// surface in the app -- this status's own isPremium/lessons.
  /// isUnlimited included, since the backend already suppresses those --
  /// should be treated as absent: hide the lesson-quota card, the
  /// Premium/Промокод menu entries, the checkmark, the profile badge.
  final bool premiumEnabled;

  /// The 9-digit account number the user puts in the transfer comment, so
  /// the admin can find who paid.
  final int publicId;

  /// Written by the admin in Admin Web and shown as-is -- a new card
  /// number never needs a new app build.
  final String priceText;
  final String paymentInstructions;

  /// Whether these automatic features are Premium-only right now, so the
  /// Premium screen lists only benefits that really are.
  final bool adaptiveLessonsPremiumOnly;
  final bool personalQuestsPremiumOnly;

  final LessonQuota lessons;

  const PremiumStatus({
    required this.isPremium,
    required this.premiumUntil,
    required this.premiumEnabled,
    required this.publicId,
    required this.priceText,
    required this.paymentInstructions,
    required this.adaptiveLessonsPremiumOnly,
    required this.personalQuestsPremiumOnly,
    required this.lessons,
  });

  factory PremiumStatus.fromJson(Map<String, dynamic> json) {
    final until = json['premium_until'] as String?;
    return PremiumStatus(
      isPremium: json['is_premium'] as bool,
      premiumUntil: until == null ? null : DateTime.parse(until).toLocal(),
      premiumEnabled: json['premium_enabled'] as bool? ?? true,
      publicId: json['public_id'] as int,
      priceText: json['price_text'] as String? ?? '',
      paymentInstructions: json['payment_instructions'] as String? ?? '',
      adaptiveLessonsPremiumOnly: json['adaptive_lessons_premium_only'] as bool? ?? true,
      personalQuestsPremiumOnly: json['personal_quests_premium_only'] as bool? ?? true,
      lessons: LessonQuota.fromJson(json['lessons'] as Map<String, dynamic>),
    );
  }
}

/// What POST /promo/redeem gave: how many days, and until when Premium
/// now runs. `message` is the backend's own ready-to-show sentence.
class PromoResult {
  final int days;
  final DateTime premiumUntil;

  /// "code" or "link".
  final String kind;

  /// True when this was the user's first video link -- the bigger reward.
  final bool isFirstLink;
  final String message;

  const PromoResult({
    required this.days,
    required this.premiumUntil,
    required this.kind,
    required this.isFirstLink,
    required this.message,
  });

  factory PromoResult.fromJson(Map<String, dynamic> json) {
    return PromoResult(
      days: json['days'] as int,
      premiumUntil: DateTime.parse(json['premium_until'] as String).toLocal(),
      kind: json['kind'] as String,
      isFirstLink: json['is_first_link'] as bool? ?? false,
      message: json['message'] as String,
    );
  }
}

/// "26.09.2026" -- the one date format Premium texts use.
String formatPremiumDate(DateTime date) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}.${two(date.month)}.${date.year}';
}
