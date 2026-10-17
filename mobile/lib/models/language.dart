/// Язык, доступный человеку: код, название и самоназвание.
///
/// Список приходит с сервера (`GET /languages`) — языки живут в базе и
/// добавляются из админки, поэтому зашитого списка в приложении нет.
class GuyoLanguage {
  final String code;
  final String name;
  final String nativeName;

  /// Переведён ли интерфейс приложения на этот язык (решает админка). Ложь --
  /// язык можно учить и читать на нём, но в переключателе интерфейса его нет:
  /// строк-то нет.
  final bool uiReady;

  const GuyoLanguage({
    required this.code,
    required this.name,
    required this.nativeName,
    this.uiReady = true,
  });

  /// Показываем самоназвание: человеку понятнее «Тоҷикӣ», чем «Таджикский».
  String get label => nativeName.isNotEmpty ? nativeName : name;

  factory GuyoLanguage.fromJson(Map<String, dynamic> json) => GuyoLanguage(
        code: json['code'] as String,
        name: json['name'] as String? ?? json['code'] as String,
        nativeName: json['native_name'] as String? ?? '',
        uiReady: json['ui_ready'] as bool? ?? true,
      );
}
