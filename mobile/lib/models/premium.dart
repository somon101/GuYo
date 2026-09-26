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
      publicId: json['public_id'] as int,
      priceText: json['price_text'] as String? ?? '',
      paymentInstructions: json['payment_instructions'] as String? ?? '',
      adaptiveLessonsPremiumOnly: json['adaptive_lessons_premium_only'] as bool? ?? true,
      personalQuestsPremiumOnly: json['personal_quests_premium_only'] as bool? ?? true,
      lessons: LessonQuota.fromJson(json['lessons'] as Map<String, dynamic>),
    );
  }
}

/// "26.09.2026" -- the one date format Premium texts use.
String formatPremiumDate(DateTime date) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}.${two(date.month)}.${date.year}';
}
