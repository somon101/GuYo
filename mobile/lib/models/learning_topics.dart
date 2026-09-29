/// Why the user is learning -- asked at sign-up and in "Мои темы". The
/// codes double as word topics on the backend (app/core/topics.py): a
/// random lesson takes words from the user's topics first. "personal" and
/// "other" have no words of their own; they just mean "no preference".
const List<({String code, String label})> learningGoals = [
  (code: 'study', label: 'Для учёбы'),
  (code: 'work', label: 'Для работы'),
  (code: 'communication', label: 'Для общения'),
  (code: 'travel', label: 'Для путешествий'),
  (code: 'relocation', label: 'Для переезда'),
  (code: 'personal', label: 'Для себя'),
  (code: 'other', label: 'Другое'),
];
