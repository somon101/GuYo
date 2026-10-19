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

  /// Опубликован ли язык для изучения и как язык перевода. Неопубликованный
  /// (чего-то не хватает -- решает проверка в админке) выбрать нельзя.
  final bool learnable;
  final bool nativeOk;

  const GuyoLanguage({
    required this.code,
    required this.name,
    required this.nativeName,
    this.uiReady = true,
    this.learnable = true,
    this.nativeOk = true,
  });

  /// Показываем самоназвание: человеку понятнее «Тоҷикӣ», чем «Таджикский».
  String get label => nativeName.isNotEmpty ? nativeName : name;

  factory GuyoLanguage.fromJson(Map<String, dynamic> json) => GuyoLanguage(
        code: json['code'] as String,
        name: json['name'] as String? ?? json['code'] as String,
        nativeName: json['native_name'] as String? ?? '',
        uiReady: json['ui_ready'] as bool? ?? true,
        // An older server does not send these: everything stays selectable.
        learnable: json['learnable'] as bool? ?? true,
        nativeOk: json['native_ok'] as bool? ?? true,
      );
}
