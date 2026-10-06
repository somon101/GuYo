import '../l10n/l10n.dart';
/// Why the user is learning -- asked at sign-up and in "Мои темы". The
/// codes double as word topics on the backend (app/core/topics.py): a
/// random lesson takes words from the user's topics first. "personal" and
/// "other" have no words of their own; they just mean "no preference".
List<({String code, String label})> get learningGoals => [
  (code: 'study', label: tr('Для учёбы')),
  (code: 'work', label: tr('Для работы')),
  (code: 'communication', label: tr('Для общения')),
  (code: 'travel', label: tr('Для путешествий')),
  (code: 'relocation', label: tr('Для переезда')),
  (code: 'personal', label: tr('Для себя')),
  (code: 'other', label: tr('Другое')),
];
