"""Server messages shown to people, in the interface language.

Routes keep raising Russian text; the handler in main.py swaps it for the
language the app sends in X-UI-Language. Text not listed here is left as is."""

# ru -> (tg, uz, en)
_TABLE: dict[str, tuple[str, str, str]] = {
    "В команде нет свободных мест": ("Дар даста ҷои холӣ нест", "Jamoada bo'sh joy yo'q", "The team has no free spots"),
    "Вы не состоите в команде": ("Шумо аъзои даста нестед", "Siz jamoada emassiz", "You are not in a team"),
    "Вы уже состоите в команде": ("Шумо аллакай дар даста ҳастед", "Siz allaqachon jamoadasiz", "You are already in a team"),
    "Задание ещё не выполнено": ("Вазифа ҳанӯз иҷро нашудааст", "Topshiriq hali bajarilmagan", "The task is not done yet"),
    "Задание не найдено": ("Вазифа ёфт нашуд", "Topshiriq topilmadi", "Task not found"),
    "Исключать может только создатель команды": ("Танҳо созандаи даста метавонад хориҷ кунад", "Faqat jamoa egasi chiqarib yubora oladi", "Only the team owner can remove members"),
    "Команда ещё не выполнила цель": ("Даста ҳанӯз ҳадафро иҷро накардааст", "Jamoa hali maqsadni bajarmagan", "The team has not reached the goal yet"),
    "Команда с таким названием уже есть": ("Даста бо чунин ном аллакай ҳаст", "Bunday nomli jamoa allaqachon bor", "A team with this name already exists"),
    "На этом уровне нет награды": ("Дар ин сатҳ мукофот нест", "Bu darajada mukofot yo'q", "There is no reward on this level"),
    "Награда уже получена": ("Мукофот аллакай гирифта шудааст", "Mukofot allaqachon olingan", "The reward has already been claimed"),
    "Неизвестная цель": ("Ҳадафи номаълум", "Noma'lum maqsad", "Unknown goal"),
    "Пригласить можно только друга": ("Танҳо дӯстро даъват кардан мумкин аст", "Faqat do'stni taklif qilish mumkin", "You can only invite a friend"),
    "Приглашать может только создатель команды": ("Танҳо созандаи даста даъват карда метавонад", "Faqat jamoa egasi taklif qila oladi", "Only the team owner can invite"),
    "Приглашение не найдено": ("Даъватнома ёфт нашуд", "Taklif topilmadi", "Invitation not found"),
    "Приглашение уже отправлено": ("Даъватнома аллакай фиристода шудааст", "Taklif allaqachon yuborilgan", "The invitation was already sent"),
    "Себя нельзя исключить: выйдите из команды": ("Худро хориҷ кардан мумкин нест: аз даста бароед", "O'zingizni chiqarib bo'lmaydi: jamoadan chiqing", "You cannot remove yourself: leave the team"),
    "Сейчас нет активного сезона": ("Ҳоло мавсими фаъол нест", "Hozir faol mavsum yo'q", "There is no active season right now"),
    "Слишком много неотвеченных приглашений": ("Даъватномаҳои беҷавоб аз ҳад зиёданд", "Javobsiz takliflar juda ko'p", "Too many unanswered invitations"),
    "Уровень ещё не достигнут": ("Сатҳ ҳанӯз ба даст наомадааст", "Daraja hali erishilmagan", "This level has not been reached yet"),
    "Цель не найдена": ("Ҳадаф ёфт нашуд", "Maqsad topilmadi", "Goal not found"),
    "Эта команда закрыта для вступления": ("Ин даста барои дохилшавӣ пӯшида аст", "Bu jamoaga qo'shilish yopiq", "This team is closed to new members"),
    "Эта награда доступна с Premium": ("Ин мукофот бо Premium дастрас аст", "Bu mukofot Premium bilan mavjud", "This reward needs Premium"),
    "Это может только создатель команды": ("Инро танҳо созандаи даста карда метавонад", "Buni faqat jamoa egasi qila oladi", "Only the team owner can do this"),
    "Этого человека нет в команде": ("Ин шахс дар даста нест", "Bu odam jamoada yo'q", "This person is not in the team"),
    "Этой награды нет в вашей коллекции": ("Ин мукофот дар маҷмӯаи шумо нест", "Bu mukofot to'plamingizda yo'q", "This reward is not in your collection"),
    "Этот человек уже состоит в команде": ("Ин шахс аллакай дар даста аст", "Bu odam allaqachon jamoada", "This person is already in a team"),
    "Сессия завершена": ("Сеанс ба охир расид", "Seans yakunlandi", "Session ended"),
    "Аккаунт удалён": ("Аккаунт нест карда шудааст", "Akkaunt o'chirilgan", "Account deleted"),
    "Обновите приложение": ("Барномаро навсозӣ кунед", "Ilovani yangilang", "Please update the app"),
}

_INDEX = {"tg": 0, "uz": 1, "en": 2}


def localize(detail, language: str | None):
    """The message in `language`, or `detail` unchanged when there is no translation."""
    idx = _INDEX.get(language or "")
    row = _TABLE.get(detail) if isinstance(detail, str) else None
    return row[idx] if row is not None and idx is not None else detail
