"""Motivating slogans for the default achievements, plus their Tajik and
Uzbek titles/slogans. Applied on server start by `apply_texts` without
overwriting anything the admin changed (see its docstring).

Key: (condition_type, condition_value) →
(title_ru, slogan_ru, title_tg, slogan_tg, title_uz, slogan_uz).
"""

TEXTS: dict[tuple[str, int], tuple[str, str, str, str, str, str]] = {
    # Открытые фразы
    ("phrases_opened", 1): (
        "Первая фраза", "Первая фраза открыта — ты уже говоришь, а не просто учишь!",
        "Ибораи аввал", "Ибораи аввал кушода шуд — ту аллакай гап мезанӣ, на танҳо меомӯзӣ!",
        "Birinchi ibora", "Birinchi ibora ochildi — sen endi shunchaki oʻrganmayapsan, gapiryapsan!"),
    ("phrases_opened", 10): (
        "Любитель фраз", "10 фраз в кармане. Слова складываются в речь — продолжай!",
        "Дӯстдори ибораҳо", "10 ибора дар кисаат. Калимаҳо ба нутқ табдил меёбанд — давом деҳ!",
        "Iboralar ishqibozi", "Choʻntagingda 10 ta ibora. Soʻzlar nutqqa aylanmoqda — davom et!"),
    ("phrases_opened", 50): (
        "Знаток фраз", "50 фраз — тебя уже понимают. Каждая новая открывает новые двери!",
        "Донандаи ибораҳо", "50 ибора — туро аллакай мефаҳманд. Ҳар ибораи нав дари навро мекушояд!",
        "Iboralar bilimdoni", "50 ta ibora — seni allaqachon tushunishadi. Har yangi ibora yangi eshik ochadi!"),
    ("phrases_opened", 100): (
        "Мастер фраз", "100 фраз! Ты справляешься с живым разговором — так держать!",
        "Устоди ибораҳо", "100 ибора! Ту аз ӯҳдаи суҳбати зинда мебароӣ — ҳамин тавр давом деҳ!",
        "Iboralar ustasi", "100 ta ibora! Sen jonli suhbatni eplay olasan — shunday davom et!"),
    ("phrases_opened", 250): (
        "Коллекционер фраз", "250 фраз — ты говоришь всё увереннее. Твой голос звучит сильнее с каждым днём!",
        "Ҷамъоварандаи ибораҳо", "250 ибора — ту боварӣ бештар гап мезанӣ. Овози ту рӯз то рӯз қавитар садо медиҳад!",
        "Iboralar kolleksioneri", "250 ta ibora — sen tobora ishonchli gapiryapsan. Ovozing kundan-kunga kuchliroq!"),
    ("phrases_opened", 500): (
        "Фразовый эксперт", "500 фраз! Ты больше не ищешь слова — они сами приходят к тебе!",
        "Коршиноси ибораҳо", "500 ибора! Ту дигар калима намеҷӯӣ — онҳо худашон ба ту меоянд!",
        "Iboralar eksperti", "500 ta ibora! Endi soʻz qidirmaysan — ular oʻzi kelib turadi!"),
    ("phrases_opened", 1000): (
        "Тысяча фраз", "Тысяча фраз! Ты достиг того, о чём другие только мечтают. Ты — пример!",
        "Ҳазор ибора", "Ҳазор ибора! Ту ба он чизе расидӣ, ки дигарон танҳо орзу мекунанд. Ту намунаӣ!",
        "Ming ibora", "Ming ibora! Boshqalar faqat orzu qilgan narsaga erishding. Sen — namunasan!"),
    # Изученные слова
    ("words_learned", 1): (
        "Первое слово", "Первый шаг сделан — дальше будет только интереснее!",
        "Калимаи аввал", "Қадами аввал гузошта шуд — минбаъд боз ҳам ҷолибтар мешавад!",
        "Birinchi soʻz", "Birinchi qadam qoʻyildi — bundan keyin yanada qiziqroq boʻladi!"),
    ("words_learned", 25): (
        "Запас растёт", "25 слов — фундамент заложен. Каждый день строй выше!",
        "Захира меафзояд", "25 калима — пойдевор гузошта шуд. Ҳар рӯз баландтар бино кун!",
        "Zaxira oʻsmoqda", "25 ta soʻz — poydevor qoʻyildi. Har kuni yanada balandroq qur!"),
    ("words_learned", 100): (
        "Сто слов", "Сотня слов — ты уже можешь объясниться. Не останавливайся!",
        "Сад калима", "Сад калима — ту аллакай фикратро фаҳмонда метавонӣ. Наист!",
        "Yuz soʻz", "Yuz soʻz — sen allaqachon fikringni tushuntira olasan. Toʻxtama!"),
    ("words_learned", 300): (
        "Полиглот", "300 слов — ты понимаешь больше, чем вчера. Мир становится ближе!",
        "Полиглот", "300 калима — ту аз дирӯз бештар мефаҳмӣ. Ҷаҳон наздиктар мешавад!",
        "Poliglot", "300 ta soʻz — kechagidan koʻproq tushunasan. Dunyo yaqinroq boʻlmoqda!"),
    ("words_learned", 500): (
        "Ходячий словарь", "500 слов! Твой словарный запас — твоя сила. Иди вперёд смело!",
        "Луғати зинда", "500 калима! Захираи луғавии ту — қуввати ту. Бо далерӣ ба пеш рав!",
        "Yuruvchi lugʻat", "500 ta soʻz! Soʻz boyliging — sening kuching. Dadil oldinga yur!"),
    ("words_learned", 1000): (
        "Легенда словаря", "Тысяча слов — ты говоришь свободнее с каждым днём. Ты легенда!",
        "Афсонаи луғат", "Ҳазор калима — ту рӯз то рӯз озодтар гап мезанӣ. Ту афсонаӣ!",
        "Lugʻat afsonasi", "Ming soʻz — kundan-kunga erkinroq gapiryapsan. Sen afsonasan!"),
    ("words_learned", 1500): (
        "Словесный титан", "1500 слов — ты на вершине, но впереди ещё выше. Покоряй дальше!",
        "Титани калимаҳо", "1500 калима — ту дар қуллаӣ, аммо пеш боз баландтар ҳаст. Фатҳ карданро давом деҳ!",
        "Soʻzlar titani", "1500 ta soʻz — choʻqqidasan, ammo oldinda yanada baland choʻqqilar bor. Zabt etishda davom et!"),
    ("words_learned", 2000): (
        "Живая энциклопедия", "Две тысячи слов. Ты доказал: невозможного нет!",
        "Энсиклопедияи зинда", "Ду ҳазор калима. Ту исбот кардӣ: ғайриимкон вуҷуд надорад!",
        "Tirik ensiklopediya", "Ikki ming soʻz. Sen isbotlading: imkonsiz narsa yoʻq!"),
    # Пройденные мини-фразы
    ("mini_phrases_done", 1): (
        "Первая мини-фраза", "Первая фраза собрана своими руками — ты уже строишь речь!",
        "Аввалин мини-ибора", "Ибораи аввал бо дасти худат ҷамъ шуд — ту аллакай нутқ месозӣ!",
        "Birinchi mini-ibora", "Birinchi ibora oʻz qoʻling bilan yigʻildi — sen endi nutq quryapsan!"),
    ("mini_phrases_done", 10): (
        "Сборщик фраз", "10 фраз собрано — из кирпичиков вырастает разговор!",
        "Ҷамъкунандаи ибораҳо", "10 ибора ҷамъ шуд — аз хиштчаҳо суҳбат месабзад!",
        "Ibora yigʻuvchi", "10 ta ibora yigʻildi — gʻishtchalardan suhbat oʻsib chiqmoqda!"),
    ("mini_phrases_done", 25): (
        "Говорю по делу", "25 фраз — ты говоришь коротко и ясно. Это и есть настоящий язык!",
        "Ба мақсад гап мезанам", "25 ибора — ту кӯтоҳ ва равшан гап мезанӣ. Забони ҳақиқӣ ҳамин аст!",
        "Mazmunli gapiraman", "25 ta ibora — qisqa va aniq gapiryapsan. Haqiqiy til mana shu!"),
    ("mini_phrases_done", 50): (
        "Уверенная речь", "50 фраз — в твоём голосе появилась уверенность. Не сбавляй темп!",
        "Нутқи боварӣ", "50 ибора — дар овози ту боварӣ пайдо шуд. Суръатро паст накун!",
        "Ishonchli nutq", "50 ta ibora — ovozingda ishonch paydo boʻldi. Sur'atni pasaytirma!"),
    ("mini_phrases_done", 100): (
        "Сто мини-фраз", "Сотня фраз! Ты готов к любому разговору — вперёд к новым высотам!",
        "Сад мини-ибора", "Сад ибора! Ту ба ҳар гуна суҳбат омодаӣ — ба сӯи қуллаҳои нав!",
        "Yuz mini-ibora", "Yuz ta ibora! Har qanday suhbatga tayyorsan — yangi choʻqqilar sari!"),
    ("mini_phrases_done", 250): (
        "Мастер общения", "250 фраз — ты общаешься как мастер. Люди слышат тебя и понимают!",
        "Устоди муошират", "250 ибора — ту мисли устод муошират мекунӣ. Одамон туро мешунаванд ва мефаҳманд!",
        "Muloqot ustasi", "250 ta ibora — sen ustadek muloqot qilasan. Odamlar seni eshitadi va tushunadi!"),
    ("mini_phrases_done", 500): (
        "Мастер мини-фраз", "500 фраз! Ты превратил учёбу в свободную речь. Это твоя победа!",
        "Устоди мини-ибораҳо", "500 ибора! Ту таҳсилро ба нутқи озод табдил додӣ. Ин ғалабаи туст!",
        "Mini-iboralar ustasi", "500 ta ibora! Oʻqishni erkin nutqqa aylantirding. Bu sening gʻalabang!"),
    # Пройденные уроки
    ("lessons_completed", 1): (
        "Первый урок", "Первый урок позади — самое трудное уже сделано: ты начал!",
        "Дарси аввал", "Дарси аввал паси сар шуд — душвортаринаш иҷро шуд: ту сар кардӣ!",
        "Birinchi dars", "Birinchi dars ortda qoldi — eng qiyini bajarildi: sen boshlading!"),
    ("lessons_completed", 5): (
        "Входишь во вкус", "5 уроков — привычка рождается. Ещё немного, и её не остановить!",
        "Завқ пайдо мекунӣ", "5 дарс — одат ба вуҷуд меояд. Каме дигар, ва онро бас кардан ғайриимкон мешавад!",
        "Ta'mini topyapsan", "5 ta dars — odat tugʻilmoqda. Yana ozgina, uni toʻxtatib boʻlmaydi!"),
    ("lessons_completed", 25): (
        "Прилежный ученик", "25 уроков — твоё упорство приносит плоды. Гордись собой!",
        "Хонандаи боғайрат", "25 дарс — истодагарии ту самар медиҳад. Аз худ фахр кун!",
        "Tirishqoq oʻquvchi", "25 ta dars — qat'iyatingning mevasini koʻryapsan. Oʻzing bilan faxrlan!"),
    ("lessons_completed", 50): (
        "Полсотни уроков", "50 уроков! Ты прошёл больше, чем многие начинают. Иди дальше!",
        "Панҷоҳ дарс", "50 дарс! Ту аз он бештар роҳ гузаштӣ, ки бисёриҳо оғоз мекунанд. Пеш рав!",
        "Ellik dars", "50 ta dars! Koʻpchilik boshlaganidan ham uzoqqa bording. Oldinga yur!"),
    ("lessons_completed", 100): (
        "Стобалльник", "100 уроков — это уже не случайность, это характер. Ты сильный!",
        "Садбаллӣ", "100 дарс — ин дигар тасодуф нест, ин хислат аст. Ту қавӣ ҳастӣ!",
        "Yuz ballik", "100 ta dars — bu endi tasodif emas, bu xarakter. Sen kuchlisan!"),
    ("lessons_completed", 200): (
        "Марафонец", "200 уроков! Ты бежишь марафон и не сбавляешь шаг. Финиш — твой!",
        "Марафончӣ", "200 дарс! Ту марафон медавӣ ва қадамро суст намекунӣ. Марра — аз они туст!",
        "Marafonchi", "200 ta dars! Marafonda yugurib, qadamingni sekinlatmaysan. Marra — seniki!"),
    # Серия дней активности
    ("streak_days", 3): (
        "Три дня подряд", "3 дня подряд — огонь зажёгся. Не дай ему погаснуть!",
        "Се рӯз пай дар пай", "3 рӯз пай дар пай — оташ даргирифт. Нагузор, ки хомӯш шавад!",
        "Uch kun ketma-ket", "3 kun ketma-ket — olov yondi. Uning soʻnishiga yoʻl qoʻyma!"),
    ("streak_days", 7): (
        "Неделя без пропусков", "Целая неделя! Привычка становится частью тебя!",
        "Ҳафтаи бе фавт", "Як ҳафтаи пурра! Одат ҷузъи вуҷуди ту мешавад!",
        "Qoldirmasdan bir hafta", "Butun bir hafta! Odat sening bir qismingga aylanmoqda!"),
    ("streak_days", 14): (
        "Две недели", "14 дней без остановки — твоя дисциплина впечатляет!",
        "Ду ҳафта", "14 рӯз бе қатъ — интизоми ту ҳайратовар аст!",
        "Ikki hafta", "14 kun toʻxtovsiz — intizoming hayratlanarli!"),
    ("streak_days", 30): (
        "Месяц дисциплины", "Месяц каждый день! Ты доказал себе, что можешь всё!",
        "Моҳи интизом", "Як моҳ ҳар рӯз! Ту ба худ исбот кардӣ, ки ҳама чизро метавонӣ!",
        "Intizom oyi", "Bir oy har kuni! Oʻzingga hamma narsani qila olishingni isbotlading!"),
    ("streak_days", 100): (
        "Сто дней огня", "100 дней подряд! Твой огонь горит ярче всех — ты вдохновляешь!",
        "Сад рӯзи оташ", "100 рӯз пай дар пай! Оташи ту аз ҳама равшантар месӯзад — ту илҳом мебахшӣ!",
        "Yuz kunlik olov", "100 kun ketma-ket! Oloving hammadan yorqin yonmoqda — sen ilhom berasan!"),
    ("streak_days", 365): (
        "Целый год!", "Год без перерыва! Ты — живое доказательство того, что упорство побеждает!",
        "Як соли пурра!", "Як сол бе танаффус! Ту далели зиндаи он ҳастӣ, ки истодагарӣ ғолиб меояд!",
        "Butun bir yil!", "Bir yil tanaffussiz! Sen qat'iyat gʻalaba qilishining tirik isbotisan!"),
    # Набрано очков
    ("points_earned", 50): (
        "Первые очки", "Первые 50 очков — счёт открыт. Дальше только вверх!",
        "Холҳои аввал", "50 холи аввал — ҳисоб кушода шуд. Минбаъд танҳо ба боло!",
        "Birinchi ochkolar", "Birinchi 50 ochko — hisob ochildi. Bundan buyon faqat yuqoriga!"),
    ("points_earned", 250): (
        "Набираешь обороты", "250 очков — ты разгоняешься. Рейтинг уже замечает тебя!",
        "Суръат мегирӣ", "250 хол — ту суръат мегирӣ. Рейтинг аллакай туро пайхас мекунад!",
        "Tezlik olyapsan", "250 ochko — tezlashyapsan. Reyting seni allaqachon payqayapti!"),
    ("points_earned", 1000): (
        "Тысячник", "1000 очков! Ты в числе лучших — держи планку высоко!",
        "Ҳазорчӣ", "1000 хол! Ту дар қатори беҳтаринҳоӣ — сатҳро баланд нигоҳ дор!",
        "Minglik", "1000 ochko! Sen eng yaxshilar qatoridasan — darajani baland tut!"),
    ("points_earned", 5000): (
        "Очковый магнат", "5000 очков! Ты на вершине рейтинга — пусть все видят, на что ты способен!",
        "Магнати холҳо", "5000 хол! Ту дар қуллаи рейтинг ҳастӣ — бигзор ҳама бубинанд, ки ту чӣ қодирӣ!",
        "Ochkolar magnati", "5000 ochko! Reyting choʻqqisidasan — hamma nimalarga qodirligingni koʻrsin!"),
    # Добавлено друзей
    ("friends_added", 1): (
        "Не один", "Первый друг рядом — вместе учиться в два раза веселее!",
        "Танҳо нестӣ", "Дӯсти аввал дар паҳлӯ — якҷоя омӯхтан ду баробар шодтар аст!",
        "Yolgʻiz emassan", "Birinchi doʻst yoningda — birga oʻrganish ikki barobar quvnoqroq!"),
    ("friends_added", 5): (
        "Компания", "5 друзей — у вас своя команда. Поддерживайте друг друга!",
        "Ҷамъият", "5 дӯст — шумо дастаи худро доред. Якдигарро дастгирӣ кунед!",
        "Davra", "5 ta doʻst — sizning oʻz jamoangiz bor. Bir-biringizni qoʻllab-quvvatlang!"),
    ("friends_added", 10): (
        "Душа компании", "10 друзей! Ты зажигаешь других — вместе вы дойдёте до вершины!",
        "Ҷони ҷамъият", "10 дӯст! Ту дигаронро рӯҳбаланд мекунӣ — якҷоя шумо ба қулла мерасед!",
        "Davraning joni", "10 ta doʻst! Sen boshqalarni ruhlantirasan — birga choʻqqiga yetasiz!"),
    # Слова в квестах
    ("quest_words_completed", 1): (
        "Первый квест", "Первый квест пройден — приключение только начинается!",
        "Квести аввал", "Квести аввал гузашт — саёҳат навакак оғоз мешавад!",
        "Birinchi kvest", "Birinchi kvest bajarildi — sarguzasht endi boshlanmoqda!"),
    ("quest_words_completed", 10): (
        "Охотник за квестами", "10 слов в квестах — ты не боишься вызовов. Вперёд за новыми!",
        "Шикорчии квестҳо", "10 калима дар квестҳо — ту аз озмоишҳо наметарсӣ. Ба сӯи навҳо!",
        "Kvest ovchisi", "Kvestlarda 10 ta soʻz — sinovlardan qoʻrqmaysan. Yangilari sari olgʻa!"),
    ("quest_words_completed", 50): (
        "Квестовый мастер", "50 слов в квестах! Любое испытание тебе по плечу — ты герой!",
        "Устоди квестҳо", "50 калима дар квестҳо! Ҳар озмоиш ба ту муяссар аст — ту қаҳрамонӣ!",
        "Kvest ustasi", "Kvestlarda 50 ta soʻz! Har qanday sinov sen uchun oson — sen qahramonsan!"),
}


def apply_texts(db) -> int:
    """For every achievement matching a default (type, value):
    - a description still equal to the old default text gets the new slogan;
    - Tajik/Uzbek title is filled (only if empty) when the title is still ours;
    - Tajik/Uzbek slogan is filled (only if empty) when the description is ours.
    Anything the admin wrote or changed stays untouched. Returns rows changed."""
    from app.models.achievement import Achievement
    from app.seed import DEFAULT_ACHIEVEMENTS

    legacy = {(t, v): desc for t, v, _title, desc, _color in DEFAULT_ACHIEVEMENTS}
    changed = 0
    for a in db.query(Achievement).all():
        texts = TEXTS.get((a.condition_type, a.condition_value))
        if texts is None:
            continue
        title_ru, slogan_ru, title_tg, slogan_tg, title_uz, slogan_uz = texts
        before = (a.description, a.title_tg, a.title_uz, a.description_tg, a.description_uz)
        if a.description == legacy.get((a.condition_type, a.condition_value)):
            a.description = slogan_ru
        if a.title == title_ru:
            a.title_tg = a.title_tg or title_tg
            a.title_uz = a.title_uz or title_uz
        if a.description == slogan_ru:
            a.description_tg = a.description_tg or slogan_tg
            a.description_uz = a.description_uz or slogan_uz
        if before != (a.description, a.title_tg, a.title_uz, a.description_tg, a.description_uz):
            changed += 1
    return changed
