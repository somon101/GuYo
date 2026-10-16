/// Язык, доступный человеку: код, название и самоназвание.
///
/// Список приходит с сервера (`GET /languages`) — языки живут в базе и
/// добавляются из админки, поэтому зашитого списка в приложении нет.
class GuyoLanguage {
  final String code;
  final String name;
  final String nativeName;

  const GuyoLanguage({required this.code, required this.name, required this.nativeName});

  /// Показываем самоназвание: человеку понятнее «Тоҷикӣ», чем «Таджикский».
  String get label => nativeName.isNotEmpty ? nativeName : name;

  factory GuyoLanguage.fromJson(Map<String, dynamic> json) => GuyoLanguage(
        code: json['code'] as String,
        name: json['name'] as String? ?? json['code'] as String,
        nativeName: json['native_name'] as String? ?? '',
      );
}
