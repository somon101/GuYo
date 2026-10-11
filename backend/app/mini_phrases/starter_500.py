"""«Набор 500»: hand-written everyday mini-phrases for the Russian dictionary.

Every line is one phrase:

    phrase | Tajik | Uzbek | English | parts

and every part is `as_written=base_word.ROLE` (or `as_written.ROLE` when the
part is the base word itself). Several candidate base words are separated
by commas — the first one found in the dictionary is used. Roles:
P pronoun, V verb, N noun, A adjective, D adverb, R preposition,
U number, O other (particles, question and service words).

Each `# Section` line starts a topic; its phrases share one template named
after it, with the general «join the parts in order» explanation.

Filled by `starter.fill_phrases` exactly like the 61-phrase starter set: a
phrase whose word is missing is skipped and reported, a missing FORM is
added to its word, existing phrases are left alone.
"""

ROLES = {
    "P": "pronoun",
    "V": "verb",
    "N": "noun",
    "A": "adjective",
    "D": "adverb",
    "R": "preposition",
    "U": "number",
    "O": "other",
}

DATA = """
# Знакомство и о себе
Как тебя зовут? | Номи ту чист? | Isming nima? | What is your name? | Как.D тебя=ты.P зовут=звать.V
Как вас зовут? | Номи шумо чист? | Ismingiz nima? | What is your name? (formal) | Как.D вас=вы.P зовут=звать.V
Откуда ты? | Ту аз куҷо ҳастӣ? | Qayerdansan? | Where are you from? | Откуда.D ты.P
Откуда вы? | Шумо аз куҷо ҳастед? | Qayerdansiz? | Where are you from? (formal) | Откуда.D вы.P
Я из Таджикистана | Ман аз Тоҷикистон ҳастам | Men Tojikistondanman | I am from Tajikistan | Я.P из.R Таджикистана=Таджикистан.N
Я из Узбекистана | Ман аз Ӯзбекистон ҳастам | Men Oʻzbekistondanman | I am from Uzbekistan | Я.P из.R Узбекистана=Узбекистан.N
Где ты живёшь? | Ту дар куҷо зиндагӣ мекунӣ? | Qayerda yashaysan? | Where do you live? | Где.D ты.P живёшь=жить.V
Я живу здесь | Ман дар ин ҷо зиндагӣ мекунам | Men shu yerda yashayman | I live here | Я.P живу=жить.V здесь.D
Я живу в Москве | Ман дар Маскав зиндагӣ мекунам | Men Moskvada yashayman | I live in Moscow | Я.P живу=жить.V в.R Москве=Москва.N
Сколько тебе лет? | Ту чандсолаӣ? | Necha yoshdasan? | How old are you? | Сколько.D тебе=ты.P лет=год.N
Мне двадцать лет | Ман бистсолаам | Men yigirma yoshdaman | I am twenty years old | Мне=я.P двадцать.U лет=год.N
Приятно познакомиться | Аз шиносоӣ бо шумо шодам | Tanishganimdan xursandman | Nice to meet you | Приятно.D познакомиться.V
Ты женат? | Ту хонадор ҳастӣ? | Uylanganmisan? | Are you married? | Ты.P женат=женатый.A
Я не женат | Ман хонадор нестам | Men uylanmaganman | I am not married | Я.P не.O женат=женатый.A
У меня есть дети | Ман фарзанд дорам | Mening bolalarim bor | I have children | У.R меня=я.P есть.V дети=ребёнок,ребенок,дети.N
У меня двое детей | Ман ду фарзанд дорам | Mening ikki farzandim bor | I have two children | У.R меня=я.P двое.U детей=ребёнок,ребенок,дети.N
Чем ты занимаешься? | Ту бо чӣ машғулӣ? | Nima ish qilasan? | What do you do? | Чем=что.O ты.P занимаешься=заниматься.V
Я работаю на стройке | Ман дар сохтмон кор мекунам | Men qurilishda ishlayman | I work at a construction site | Я.P работаю=работать.V на.R стройке=стройка.N
Я студент | Ман донишҷӯ ҳастам | Men talabaman | I am a student | Я.P студент.N
Я водитель | Ман ронанда ҳастам | Men haydovchiman | I am a driver | Я.P водитель.N
Я плохо говорю по-русски | Ман ба забони русӣ бад гап мезанам | Men ruschani yomon gapiraman | I speak Russian poorly | Я.P плохо.D говорю=говорить.V по-русски=по-русски,русский.D
Я немного понимаю по-русски | Ман каме русӣ мефаҳмам | Men ruschani biroz tushunaman | I understand a little Russian | Я.P немного.D понимаю=понимать.V по-русски=по-русски,русский.D
Ты говоришь по-русски? | Ту русӣ гап мезанӣ? | Ruscha gapirasanmi? | Do you speak Russian? | Ты.P говоришь=говорить.V по-русски=по-русски,русский.D
Я учу русский язык | Ман забони русиро меомӯзам | Men rus tilini oʻrganyapman | I am learning Russian | Я.P учу=учить.V русский.A язык.N
Это мой друг | Ин дӯсти ман аст | Bu mening doʻstim | This is my friend | Это.O мой.P друг.N
Это моя жена | Ин зани ман аст | Bu mening xotinim | This is my wife | Это.O моя=мой.P жена.N
Это мой брат | Ин бародари ман аст | Bu mening akam | This is my brother | Это.O мой.P брат.N
Рад тебя видеть | Аз дидани ту шодам | Seni koʻrganimdan xursandman | Glad to see you | Рад=рад,радый.A тебя=ты.P видеть.V
Давно не виделись | Кайҳо боз надидем | Koʻrishmaganimizga ancha boʻldi | Long time no see | Давно.D не.O виделись=видеться,видеть.V
Как дела? | Корҳо чӣ хел? | Ishlar qalay? | How are you? | Как.D дела=дело.N
У меня всё хорошо | Корҳоям хуб аст | Mening ishlarim yaxshi | I am fine | У.R меня=я.P всё=всё,весь.O хорошо.D
А у тебя? | Худат чӣ? | Oʻzingda-chi? | And you? | А.O у.R тебя=ты.P
Где ты работаешь? | Ту дар куҷо кор мекунӣ? | Qayerda ishlaysan? | Where do you work? | Где.D ты.P работаешь=работать.V
Я здесь недавно | Ман ин ҷо нав омадаам | Men bu yerga yaqinda keldim | I am new here | Я.P здесь.D недавно.D
Я приехал на работу | Ман барои кор омадам | Men ishlash uchun keldim | I came here to work | Я.P приехал=приехать.V на.R работу=работа.N
Давай дружить | Биё дӯст шавем | Keling, doʻst boʻlaylik | Let's be friends | Давай=давать.V дружить.V
Вот мой номер | Ана рақами ман | Mana mening raqamim | Here is my number | Вот.O мой.P номер.N

# Вежливость
Доброе утро | Субҳ ба хайр | Xayrli tong | Good morning | Доброе=добрый.A утро.N
Добрый день | Рӯз ба хайр | Xayrli kun | Good afternoon | Добрый.A день.N
Добрый вечер | Шом ба хайр | Xayrli kech | Good evening | Добрый.A вечер.N
Спокойной ночи | Шаб ба хайр | Xayrli tun | Good night | Спокойной=спокойный.A ночи=ночь.N
До свидания | То дидан | Xayr, koʻrishguncha | Goodbye | До.R свидания=свидание.N
До завтра | То фардо | Ertagacha | See you tomorrow | До.R завтра.D
До встречи | То вохӯрӣ | Koʻrishguncha | See you | До.R встречи=встреча.N
Большое спасибо | Ташаккури зиёд | Katta rahmat | Thank you very much | Большое=большой.A спасибо.O
Спасибо за помощь | Ташаккур барои ёрӣ | Yordam uchun rahmat | Thanks for the help | Спасибо.O за.R помощь.N
Не за что | Намеарзад | Arzimaydi | You're welcome | Не.O за.R что.O
Извините, пожалуйста | Бубахшед, лутфан | Kechirasiz, iltimos | Excuse me, please | Извините=извинить.V пожалуйста.O
Простите меня | Маро бубахшед | Meni kechiring | Forgive me | Простите=простить.V меня=я.P
Я не хотел | Ман қасдан накардам | Men ataylab qilmadim | I didn't mean it | Я.P не.O хотел=хотеть.V
Ничего страшного | Ҳеҷ гап не | Hechqisi yoʻq | It's okay | Ничего.O страшного=страшный.A
Всё в порядке | Ҳамааш хуб аст | Hammasi joyida | Everything is fine | Всё=всё,весь.O в.R порядке=порядок.N
Будьте добры | Илтифот кунед | Marhamat qiling | Would you be so kind | Будьте=быть.V добры=добрый.A
Можно войти? | Даромадан мумкин? | Kirsam boʻladimi? | May I come in? | Можно.O войти.V
Можно спросить? | Пурсидан мумкин? | Soʻrasam boʻladimi? | May I ask? | Можно.O спросить.V
Садитесь, пожалуйста | Лутфан, нишинед | Iltimos, oʻtiring | Please sit down | Садитесь=садиться.V пожалуйста.O
Приятного аппетита | Иштиҳои гуворо | Yoqimli ishtaha | Enjoy your meal | Приятного=приятный.A аппетита=аппетит.N
Будь здоров | Саломат бош | Sogʻ boʻl | Bless you | Будь=быть.V здоров=здоровый.A
С днём рождения | Зодрӯзат муборак | Tugʻilgan kuning bilan | Happy birthday | С.R днём=день.N рождения=рождение.N
С праздником | Ид муборак | Bayram bilan | Happy holiday | С.R праздником=праздник.N
Удачи тебе | Барори кор ба ту | Senga omad | Good luck | Удачи=удача.N тебе=ты.P
Счастливого пути | Роҳи сафед | Oq yoʻl | Have a good trip | Счастливого=счастливый.A пути=путь.N
Не беспокойтесь | Ташвиш накашед | Xavotir olmang | Don't worry | Не.O беспокойтесь=беспокоиться.V
Передай привет маме | Ба модар салом расон | Onangga salom ayt | Say hi to mom | Передай=передать.V привет.N маме=мама.N
Мне очень жаль | Хеле афсӯс мехӯрам | Juda afsusdaman | I am very sorry | Мне=я.P очень.D жаль.O
Добро пожаловать | Хуш омадед | Xush kelibsiz | Welcome | Добро.N пожаловать.V

# Понимание и язык
Я не понимаю | Ман намефаҳмам | Men tushunmayapman | I don't understand | Я.P не.O понимаю=понимать.V
Я понял | Ман фаҳмидам | Tushundim | I understood | Я.P понял=понять.V
Ты понял? | Ту фаҳмидӣ? | Tushundingmi? | Did you understand? | Ты.P понял=понять.V
Повторите, пожалуйста | Лутфан, такрор кунед | Iltimos, takrorlang | Please repeat | Повторите=повторить.V пожалуйста.O
Говорите медленнее | Оҳистатар гап занед | Sekinroq gapiring | Speak more slowly | Говорите=говорить.V медленнее=медленно.D
Что это значит? | Ин чӣ маъно дорад? | Bu nimani anglatadi? | What does this mean? | Что.O это.O значит=значить.V
Как это сказать по-русски? | Инро бо русӣ чӣ хел мегӯянд? | Buni ruscha qanday aytiladi? | How do you say this in Russian? | Как.D это.O сказать.V по-русски=по-русски,русский.D
Напишите, пожалуйста | Лутфан, нависед | Iltimos, yozib bering | Please write it down | Напишите=написать.V пожалуйста.O
Я не знаю | Ман намедонам | Bilmayman | I don't know | Я.P не.O знаю=знать.V
Я забыл | Ман фаромӯш кардам | Esimdan chiqdi | I forgot | Я.P забыл=забыть.V
Я помню | Ман дар ёд дорам | Esimda | I remember | Я.P помню=помнить.V
Объясните ещё раз | Боз як бор фаҳмонед | Yana bir marta tushuntiring | Explain once more | Объясните=объяснить.V ещё=ещё,еще.D раз.N
Я правильно говорю? | Ман дуруст мегӯям? | Toʻgʻri gapiryapmanmi? | Am I saying it right? | Я.P правильно.D говорю=говорить.V
Как правильно? | Чӣ хел дуруст аст? | Qanday toʻgʻri? | What is the correct way? | Как.D правильно.D
Я не расслышал | Ман нашунидам | Eshitmay qoldim | I didn't hear | Я.P не.O расслышал=расслышать.V
Громче, пожалуйста | Лутфан, баландтар | Iltimos, balandroq | Louder, please | Громче=громко.D пожалуйста.O
Что ты сказал? | Ту чӣ гуфтӣ? | Nima deding? | What did you say? | Что.O ты.P сказал=сказать.V
Я плохо слышу | Ман бад мешунавам | Men yomon eshitaman | I hear badly | Я.P плохо.D слышу=слышать.V
Переведите, пожалуйста | Лутфан, тарҷума кунед | Iltimos, tarjima qiling | Please translate | Переведите=перевести.V пожалуйста.O
Это трудное слово | Ин калимаи душвор аст | Bu qiyin soʻz | This is a difficult word | Это.O трудное=трудный.A слово.N
Покажите на карте | Дар харита нишон диҳед | Xaritada koʻrsating | Show me on the map | Покажите=показать.V на.R карте=карта.N
Вы меня понимаете? | Шумо маро мефаҳмед? | Meni tushunyapsizmi? | Do you understand me? | Вы.P меня=я.P понимаете=понимать.V
Я учусь говорить | Ман гап заданро меомӯзам | Gapirishni oʻrganyapman | I am learning to speak | Я.P учусь=учиться.V говорить.V

# Вопросы
Где туалет? | Ҳоҷатхона дар куҷост? | Hojatxona qayerda? | Where is the toilet? | Где.D туалет.N
Сколько это стоит? | Ин чанд пул аст? | Bu qancha turadi? | How much does it cost? | Сколько.D это.O стоит=стоить.V
Который час? | Соат чанд аст? | Soat necha? | What time is it? | Который.A час.N
Что случилось? | Чӣ шуд? | Nima boʻldi? | What happened? | Что.O случилось=случиться.V
Почему ты молчишь? | Чаро хомӯшӣ? | Nega jimsan? | Why are you silent? | Почему.D ты.P молчишь=молчать.V
Кто это? | Ин кист? | Bu kim? | Who is this? | Кто.O это.O
Что это? | Ин чист? | Bu nima? | What is this? | Что.O это.O
Куда ты идёшь? | Ту ба куҷо меравӣ? | Qayerga ketyapsan? | Where are you going? | Куда.D ты.P идёшь=идти.V
Когда ты придёшь? | Ту кай меоӣ? | Qachon kelasan? | When will you come? | Когда.D ты.P придёшь=прийти.V
Ты где? | Ту дар куҷоӣ? | Qayerdasan? | Where are you? | Ты.P где.D
Можно тебя попросить? | Аз ту хоҳиш кунам мумкин? | Sendan iltimos qilsam boʻladimi? | Can I ask you a favor? | Можно.O тебя=ты.P попросить.V
Ты свободен? | Ту холӣ ҳастӣ? | Boʻshmisan? | Are you free? | Ты.P свободен=свободный.A
У тебя есть время? | Ту вақт дорӣ? | Vaqting bormi? | Do you have time? | У.R тебя=ты.P есть.V время.N
Как это работает? | Ин чӣ хел кор мекунад? | Bu qanday ishlaydi? | How does this work? | Как.D это.O работает=работать.V
Сколько нужно ждать? | Чӣ қадар интизор шудан лозим? | Qancha kutish kerak? | How long do I need to wait? | Сколько.D нужно.O ждать.V
Ты уверен? | Ту боварӣ дорӣ? | Ishonching komilmi? | Are you sure? | Ты.P уверен=уверенный.A
Это правда? | Ин рост аст? | Bu rostmi? | Is it true? | Это.O правда.N
Как тебе здесь? | Ба ту ин ҷо чӣ хел? | Bu yer senga qalay? | How do you like it here? | Как.D тебе=ты.P здесь.D
Где ты был? | Ту дар куҷо будӣ? | Qayerda eding? | Where were you? | Где.D ты.P был=быть.V
С кем ты живёшь? | Ту бо кӣ зиндагӣ мекунӣ? | Kim bilan yashaysan? | Who do you live with? | С.R кем=кто.O ты.P живёшь=жить.V
Зачем это нужно? | Ин барои чӣ лозим? | Bu nima uchun kerak? | Why is this needed? | Зачем.D это.O нужно.O
Что ты хочешь? | Ту чӣ мехоҳӣ? | Nima xohlaysan? | What do you want? | Что.O ты.P хочешь=хотеть.V
Чей это телефон? | Ин телефони кист? | Bu kimning telefoni? | Whose phone is this? | Чей.O это.O телефон.N

# Магазин и деньги
Дайте, пожалуйста, хлеб | Лутфан, нон диҳед | Iltimos, non bering | Bread, please | Дайте=дать.V пожалуйста.O хлеб.N
Мне нужен пакет | Ба ман халта лозим | Menga paket kerak | I need a bag | Мне=я.P нужен=нужный.A пакет.N
Это слишком дорого | Ин хеле қимат аст | Bu juda qimmat | This is too expensive | Это.O слишком.D дорого.D
А подешевле есть? | Арзонтараш ҳаст? | Arzonrogʻi bormi? | Is there something cheaper? | А.O подешевле=дёшево,дешево,дешёвый.D есть.V
Можно посмотреть? | Дидан мумкин? | Koʻrsam boʻladimi? | Can I take a look? | Можно.O посмотреть.V
Я просто смотрю | Ман фақат тамошо мекунам | Shunchaki koʻryapman | I'm just looking | Я.P просто.D смотрю=смотреть.V
Я возьму это | Ман инро мегирам | Men buni olaman | I'll take this | Я.P возьму=взять.V это.O
Можно картой? | Бо корт мумкин? | Karta bilan boʻladimi? | Can I pay by card? | Можно.O картой=карта.N
Я заплачу наличными | Ман нақд пардохт мекунам | Naqd toʻlayman | I'll pay in cash | Я.P заплачу=заплатить.V наличными=наличные.N
Дайте сдачу | Бақияро диҳед | Qaytimni bering | Give me the change | Дайте=дать.V сдачу=сдача.N
Где касса? | Касса дар куҷост? | Kassa qayerda? | Where is the checkout? | Где.D касса.N
У вас есть молоко? | Шумо шир доред? | Sizda sut bormi? | Do you have milk? | У.R вас=вы.P есть.V молоко.N
Сколько стоит килограмм? | Як кило чанд пул? | Bir kilosi qancha? | How much is a kilo? | Сколько.D стоит=стоить.V килограмм.N
Дайте два килограмма | Ду кило диҳед | Ikki kilo bering | Give me two kilos | Дайте=дать.V два.U килограмма=килограмм.N
Это свежее? | Ин тоза аст? | Bu yangimi? | Is this fresh? | Это.O свежее=свежий.A
Мне нужно купить обувь | Ба ман пойафзол харидан лозим | Menga oyoq kiyim sotib olish kerak | I need to buy shoes | Мне=я.P нужно.O купить.V обувь.N
Какой это размер? | Ин чӣ андоза аст? | Bu qaysi oʻlcham? | What size is this? | Какой.A это.O размер.N
Можно примерить? | Пӯшида бинам мумкин? | Kiyib koʻrsam boʻladimi? | Can I try it on? | Можно.O примерить.V
Это мне мало | Ин ба ман хурд аст | Bu menga kichik | This is too small for me | Это.O мне=я.P мало.D
Это мне велико | Ин ба ман калон аст | Bu menga katta | This is too big for me | Это.O мне=я.P велико=великий.A
Где можно купить телефон? | Телефонро аз куҷо харидан мумкин? | Telefonni qayerdan sotib olsa boʻladi? | Where can I buy a phone? | Где.D можно.O купить.V телефон.N
Магазин уже закрыт | Мағоза аллакай баста аст | Doʻkon allaqachon yopiq | The shop is already closed | Магазин.N уже.D закрыт=закрытый.A
Когда открывается рынок? | Бозор кай кушода мешавад? | Bozor qachon ochiladi? | When does the market open? | Когда.D открывается=открываться.V рынок.N
У меня нет денег | Ман пул надорам | Pulim yoʻq | I have no money | У.R меня=я.P нет.O денег=деньги.N
Мне не хватает денег | Пулам намерасад | Pulim yetmaydi | I don't have enough money | Мне=я.P не.O хватает=хватать.V денег=деньги.N
Я получил зарплату | Ман маош гирифтам | Men maosh oldim | I got my salary | Я.P получил=получить.V зарплату=зарплата.N
Где ближайший банкомат? | Банкомати наздиктарин дар куҷост? | Eng yaqin bankomat qayerda? | Where is the nearest ATM? | Где.D ближайший.A банкомат.N
Я хочу отправить деньги | Ман мехоҳам пул фиристам | Men pul joʻnatmoqchiman | I want to send money | Я.P хочу=хотеть.V отправить.V деньги.N
Одолжи мне денег | Ба ман қарз деҳ | Menga qarz ber | Lend me some money | Одолжи=одолжить.V мне=я.P денег=деньги.N
Я верну завтра | Ман фардо бармегардонам | Ertaga qaytaraman | I'll pay it back tomorrow | Я.P верну=вернуть.V завтра.D
Это бесплатно? | Ин ройгон аст? | Bu bepulmi? | Is it free? | Это.O бесплатно.D
Есть скидка? | Тахфиф ҳаст? | Chegirma bormi? | Is there a discount? | Есть.V скидка.N
Дайте чек, пожалуйста | Лутфан, чекро диҳед | Iltimos, chekni bering | The receipt, please | Дайте=дать.V чек.N пожалуйста.O
Я хочу вернуть товар | Ман мехоҳам молро баргардонам | Tovarni qaytarmoqchiman | I want to return the item | Я.P хочу=хотеть.V вернуть.V товар.N
Здесь есть аптека? | Ин ҷо дорухона ҳаст? | Bu yerda dorixona bormi? | Is there a pharmacy here? | Здесь.D есть.V аптека.N

# Транспорт и дорога
Как доехать до центра? | Ба марказ чӣ хел рафтан мумкин? | Markazga qanday borsa boʻladi? | How do I get to the center? | Как.D доехать.V до.R центра=центр.N
Где остановка автобуса? | Истгоҳи автобус дар куҷост? | Avtobus bekati qayerda? | Where is the bus stop? | Где.D остановка.N автобуса=автобус.N
Какой автобус идёт туда? | Кадом автобус ба он ҷо меравад? | U yerga qaysi avtobus boradi? | Which bus goes there? | Какой.A автобус.N идёт=идти.V туда.D
Где метро? | Метро дар куҷост? | Metro qayerda? | Where is the metro? | Где.D метро.N
Мне нужно на вокзал | Ба ман ба вокзал рафтан лозим | Menga vokzalga borish kerak | I need to get to the station | Мне=я.P нужно.O на.R вокзал.N
Остановите здесь, пожалуйста | Лутфан, ин ҷо истед | Iltimos, shu yerda toʻxtating | Stop here, please | Остановите=остановить.V здесь.D пожалуйста.O
Сколько стоит билет? | Чипта чанд пул аст? | Chipta qancha turadi? | How much is a ticket? | Сколько.D стоит=стоить.V билет.N
Один билет, пожалуйста | Як чипта, лутфан | Bitta chipta, iltimos | One ticket, please | Один.U билет.N пожалуйста.O
Это далеко? | Ин дур аст? | Bu uzoqmi? | Is it far? | Это.O далеко.D
Это близко | Ин наздик аст | Bu yaqin | It's close | Это.O близко.D
Идите прямо | Рост равед | Toʻgʻriga yuring | Go straight | Идите=идти.V прямо.D
Поверните направо | Ба тарафи рост гардед | Oʻngga buriling | Turn right | Поверните=повернуть.V направо.D
Поверните налево | Ба тарафи чап гардед | Chapga buriling | Turn left | Поверните=повернуть.V налево.D
Я заблудился | Ман роҳро гум кардам | Adashib qoldim | I am lost | Я.P заблудился=заблудиться.V
Покажите дорогу | Роҳро нишон диҳед | Yoʻlni koʻrsating | Show me the way | Покажите=показать.V дорогу=дорога.N
Вызовите такси | Такси ҷеғ занед | Taksi chaqiring | Call a taxi | Вызовите=вызвать.V такси.N
Сколько ехать? | Чӣ қадар роҳ аст? | Qancha yuriladi? | How long is the ride? | Сколько.D ехать.V
Я опаздываю на работу | Ман ба кор дер мемонам | Ishga kechikyapman | I'm late for work | Я.P опаздываю=опаздывать.V на.R работу=работа.N
Автобус опоздал | Автобус дер кард | Avtobus kechikdi | The bus was late | Автобус.N опоздал=опоздать.V
Следующая остановка моя | Истгоҳи навбатӣ аз они ман | Keyingi bekat meniki | The next stop is mine | Следующая=следующий.A остановка.N моя=мой.P
Здесь свободно? | Ин ҷо холӣ аст? | Bu yer boʻshmi? | Is this seat free? | Здесь.D свободно.D
Где выход? | Баромадгоҳ дар куҷост? | Chiqish qayerda? | Where is the exit? | Где.D выход.N
Мне выходить здесь? | Ман ин ҷо фуроям? | Shu yerda tushaymi? | Should I get off here? | Мне=я.P выходить.V здесь.D
Поезд уже ушёл | Қатора аллакай рафт | Poyezd allaqachon ketdi | The train has already left | Поезд.N уже.D ушёл=уйти.V
Когда следующий поезд? | Қатораи навбатӣ кай аст? | Keyingi poyezd qachon? | When is the next train? | Когда.D следующий.A поезд.N
Я еду домой | Ман ба хона меравам | Uyga ketyapman | I'm going home | Я.P еду=ехать.V домой.D
Подвезите меня, пожалуйста | Лутфан, маро бо худ баред | Iltimos, meni olib boring | Give me a ride, please | Подвезите=подвезти.V меня=я.P пожалуйста.O
Здесь большая пробка | Ин ҷо тиқмаи калон аст | Bu yerda katta tirbandlik | There's a big traffic jam here | Здесь.D большая=большой.A пробка.N
Пристегните ремень | Камарбандро бандед | Kamarni taqing | Fasten your seat belt | Пристегните=пристегнуть.V ремень.N
Я куплю билет онлайн | Ман чиптаро онлайн мехарам | Chiptani onlayn olaman | I'll buy the ticket online | Я.P куплю=купить.V билет.N онлайн.D
Это прямой рейс? | Ин парвози мустақим аст? | Bu toʻgʻri reysmi? | Is it a direct flight? | Это.O прямой.A рейс.N
Мой самолёт задерживается | Ҳавопаймои ман дер мекунад | Samolyotim kechikyapti | My plane is delayed | Мой.P самолёт=самолёт,самолет.N задерживается=задерживаться.V
Где мой багаж? | Бағоҷи ман дар куҷост? | Bagajim qayerda? | Where is my luggage? | Где.D мой.P багаж.N
Я жду тебя у входа | Ман туро дар назди даромадгоҳ интизорам | Seni kirish oldida kutyapman | I'm waiting for you at the entrance | Я.P жду=ждать.V тебя=ты.P у.R входа=вход.N
Пешком десять минут | Пиёда даҳ дақиқа | Piyoda oʻn daqiqa | Ten minutes on foot | Пешком.D десять.U минут=минута.N

# Работа
Я ищу работу | Ман кор меҷӯям | Men ish qidiryapman | I am looking for work | Я.P ищу=искать.V работу=работа.N
У вас есть работа? | Шумо кор доред? | Sizda ish bormi? | Do you have work? | У.R вас=вы.P есть.V работа.N
Сколько вы платите? | Шумо чӣ қадар музд медиҳед? | Qancha toʻlaysiz? | How much do you pay? | Сколько.D вы.P платите=платить.V
Когда начинать работу? | Корро кай сар кунам? | Ishni qachon boshlash kerak? | When do I start work? | Когда.D начинать.V работу=работа.N
Я могу начать завтра | Ман фардо сар карда метавонам | Ertaga boshlay olaman | I can start tomorrow | Я.P могу=мочь.V начать.V завтра.D
У меня есть опыт | Ман таҷриба дорам | Tajribam bor | I have experience | У.R меня=я.P есть.V опыт.N
Я умею водить машину | Ман мошин ронда метавонам | Men mashina hayday olaman | I can drive a car | Я.P умею=уметь.V водить.V машину=машина.N
Я быстро учусь | Ман зуд меомӯзам | Men tez oʻrganaman | I learn fast | Я.P быстро.D учусь=учиться.V
Во сколько обед? | Хӯроки нисфирӯзӣ соати чанд? | Tushlik soat nechada? | What time is lunch? | Во=в.R сколько.D обед.N
Я работаю без выходных | Ман бе рӯзи истироҳат кор мекунам | Dam olishsiz ishlayman | I work without days off | Я.P работаю=работать.V без.R выходных=выходной.N
Завтра у меня выходной | Фардо ман рӯзи истироҳат дорам | Ertaga dam olish kunim | Tomorrow is my day off | Завтра.D у.R меня=я.P выходной.N
Я устал | Ман хаста шудам | Charchadim | I am tired | Я.P устал=устать.V
Мне нужен перерыв | Ба ман танаффус лозим | Menga tanaffus kerak | I need a break | Мне=я.P нужен=нужный.A перерыв.N
Я закончил работу | Ман корро тамом кардам | Ishni tugatdim | I finished the work | Я.P закончил=закончить.V работу=работа.N
Что мне делать дальше? | Минбаъд чӣ кор кунам? | Keyin nima qilay? | What should I do next? | Что.O мне=я.P делать.V дальше.D
Покажите, как это делать | Нишон диҳед, ки инро чӣ хел мекунанд | Buni qanday qilishni koʻrsating | Show me how to do it | Покажите=показать.V как.D это.O делать.V
Где мои инструменты? | Асбобҳои ман дар куҷоянд? | Asboblarim qayerda? | Where are my tools? | Где.D мои=мой.P инструменты=инструмент.N
Мне не заплатили | Ба ман музд надоданд | Menga pul toʻlashmadi | They didn't pay me | Мне=я.P не.O заплатили=заплатить.V
Когда будет зарплата? | Маош кай мешавад? | Maosh qachon boʻladi? | When is payday? | Когда.D будет=быть.V зарплата.N
Я хочу работать больше | Ман мехоҳам бештар кор кунам | Koʻproq ishlamoqchiman | I want to work more | Я.P хочу=хотеть.V работать.V больше.D
Нужен договор | Шартнома лозим аст | Shartnoma kerak | A contract is needed | Нужен=нужный.A договор.N
Я подпишу договор | Ман шартномаро имзо мекунам | Shartnomani imzolayman | I will sign the contract | Я.P подпишу=подписать.V договор.N
Это моя смена | Ин навбати кории ман аст | Bu mening smenam | This is my shift | Это.O моя=мой.P смена.N
Я работаю ночью | Ман шабона кор мекунам | Kechasi ishlayman | I work at night | Я.P работаю=работать.V ночью.D
Начальник здесь? | Сардор ин ҷост? | Boshliq shu yerdami? | Is the boss here? | Начальник.N здесь.D
Мне нужна справка | Ба ман маълумотнома лозим | Menga maʼlumotnoma kerak | I need a certificate | Мне=я.P нужна=нужный.A справка.N
Я сделаю это сегодня | Ман инро имрӯз мекунам | Buni bugun qilaman | I'll do it today | Я.P сделаю=сделать.V это.O сегодня.D
Работа тяжёлая | Кор вазнин аст | Ish ogʻir | The work is hard | Работа.N тяжёлая=тяжёлый,тяжелый.A
Я опоздал, извините | Ман дер кардам, бубахшед | Kechikdim, kechirasiz | I'm late, sorry | Я.P опоздал=опоздать.V извините=извинить.V
Можно уйти пораньше? | Барвақттар рафтан мумкин? | Ertaroq ketsam boʻladimi? | Can I leave a bit earlier? | Можно.O уйти.V пораньше=рано.D
У меня есть разрешение | Ман иҷозатнома дорам | Ruxsatnomam bor | I have a permit | У.R меня=я.P есть.V разрешение.N
Где отдел кадров? | Шӯъбаи кадрҳо дар куҷост? | Kadrlar boʻlimi qayerda? | Where is HR? | Где.D отдел.N кадров=кадры,кадр.N
Работаем вместе | Якҷоя кор мекунем | Birga ishlaymiz | We work together | Работаем=работать.V вместе.D
Помоги мне поднять | Ба ман бардоштан ёрӣ деҳ | Koʻtarishga yordam ber | Help me lift it | Помоги=помочь.V мне=я.P поднять.V
Осторожно, тяжело | Эҳтиёт, вазнин аст | Ehtiyot boʻl, ogʻir | Careful, it's heavy | Осторожно.D тяжело.D
Я новый работник | Ман коргари нав ҳастам | Men yangi xodimman | I am a new worker | Я.P новый.A работник.N
Сколько часов работать? | Чанд соат кор кардан лозим? | Necha soat ishlash kerak? | How many hours do I work? | Сколько.D часов=час.N работать.V
Я согласен на эту работу | Ман ба ин кор розӣ ҳастам | Bu ishga roziman | I agree to this job | Я.P согласен=согласный.A на.R эту=этот.P работу=работа.N
Мне нужна форма | Ба ман либоси корӣ лозим | Menga ish kiyimi kerak | I need a uniform | Мне=я.P нужна=нужный.A форма.N
Я позвоню начальнику | Ман ба сардор занг мезанам | Boshliqqa qoʻngʻiroq qilaman | I'll call the boss | Я.P позвоню=позвонить.V начальнику=начальник.N

# Учёба
Я учусь в университете | Ман дар донишгоҳ мехонам | Universitetda oʻqiyman | I study at university | Я.P учусь=учиться.V в.R университете=университет.N
Где моя тетрадь? | Дафтари ман дар куҷост? | Daftarim qayerda? | Where is my notebook? | Где.D моя=мой.P тетрадь.N
Урок начался | Дарс сар шуд | Dars boshlandi | The lesson has started | Урок.N начался=начаться.V
Я сделал домашнее задание | Ман вазифаи хонагиро иҷро кардам | Uy vazifasini qildim | I did my homework | Я.P сделал=сделать.V домашнее=домашний.A задание.N
Учитель объясняет хорошо | Муаллим хуб мефаҳмонад | Oʻqituvchi yaxshi tushuntiradi | The teacher explains well | Учитель.N объясняет=объяснять,объяснить.V хорошо.D
Можно задать вопрос? | Савол додан мумкин? | Savol bersam boʻladimi? | May I ask a question? | Можно.O задать.V вопрос.N
Я сдал экзамен | Ман имтиҳон супоридам | Imtihondan oʻtdim | I passed the exam | Я.P сдал=сдать.V экзамен.N
Я готовлюсь к экзамену | Ман ба имтиҳон тайёрӣ мебинам | Imtihonga tayyorlanyapman | I'm preparing for the exam | Я.P готовлюсь=готовиться.V к.R экзамену=экзамен.N
Дай ручку, пожалуйста | Лутфан, ручкаро деҳ | Iltimos, ruchkani ber | Give me a pen, please | Дай=дать.V ручку=ручка.N пожалуйста.O
Я читаю книгу | Ман китоб мехонам | Kitob oʻqiyapman | I am reading a book | Я.P читаю=читать.V книгу=книга.N
Откройте учебник | Китоби дарсиро кушоед | Darslikni oching | Open the textbook | Откройте=открыть.V учебник.N
Какая сегодня тема? | Мавзӯи имрӯза чист? | Bugungi mavzu nima? | What is today's topic? | Какая=какой.A сегодня.D тема.N
Занятие отменили | Машғулотро бекор карданд | Mashgʻulot bekor qilindi | The class was cancelled | Занятие.N отменили=отменить.V
Я хочу учиться дальше | Ман мехоҳам хониданро идома диҳам | Oʻqishni davom ettirmoqchiman | I want to continue studying | Я.P хочу=хотеть.V учиться.V дальше.D
Мой сын ходит в школу | Писари ман ба мактаб меравад | Oʻgʻlim maktabga boradi | My son goes to school | Мой.P сын.N ходит=ходить.V в.R школу=школа.N
Сколько стоят курсы? | Курсҳо чанд пул аст? | Kurslar qancha turadi? | How much are the courses? | Сколько.D стоят=стоить.V курсы=курс.N
Я записался на курсы | Ман ба курсҳо номнавис шудам | Kurslarga yozildim | I signed up for courses | Я.P записался=записаться.V на.R курсы=курс.N
Это лёгкий вопрос | Ин саволи осон аст | Bu oson savol | This is an easy question | Это.O лёгкий=лёгкий,легкий.A вопрос.N
Я получил диплом | Ман диплом гирифтам | Diplom oldim | I got my diploma | Я.P получил=получить.V диплом.N

# Врач и здоровье
Мне плохо | Ҳоли ман бад аст | Ahvolim yomon | I feel bad | Мне=я.P плохо.D
У меня болит голова | Сарам дард мекунад | Boshim ogʻriyapti | I have a headache | У.R меня=я.P болит=болеть.V голова.N
У меня болит живот | Шикамам дард мекунад | Qornim ogʻriyapti | I have a stomachache | У.R меня=я.P болит=болеть.V живот.N
У меня болит зуб | Дандонам дард мекунад | Tishim ogʻriyapti | I have a toothache | У.R меня=я.P болит=болеть.V зуб.N
У меня температура | Ман таб дорам | Isitmam bor | I have a fever | У.R меня=я.P температура.N
Вызовите скорую | Ёрии таъҷилиро ҷеғ занед | Tez yordam chaqiring | Call an ambulance | Вызовите=вызвать.V скорую=скорая,скорый.A
Мне нужен врач | Ба ман духтур лозим | Menga shifokor kerak | I need a doctor | Мне=я.P нужен=нужный.A врач.N
Где больница? | Беморхона дар куҷост? | Kasalxona qayerda? | Where is the hospital? | Где.D больница.N
Я заболел | Ман бемор шудам | Kasal boʻlib qoldim | I got sick | Я.P заболел=заболеть.V
Я простудился | Ман шамол хӯрдам | Shamollab qoldim | I caught a cold | Я.P простудился=простудиться.V
Я кашляю | Ман сулфа мекунам | Yoʻtalyapman | I'm coughing | Я.P кашляю=кашлять.V
У меня аллергия | Ман аллергия дорам | Menda allergiya bor | I have an allergy | У.R меня=я.P аллергия.N
Дайте лекарство от боли | Доруи зидди дард диҳед | Ogʻriq uchun dori bering | Give me a painkiller | Дайте=дать.V лекарство.N от.R боли=боль.N
Как принимать лекарство? | Доруро чӣ хел бояд истеъмол кард? | Dorini qanday ichish kerak? | How do I take the medicine? | Как.D принимать.V лекарство.N
Мне нужен рецепт? | Ба ман дорухат лозим? | Menga retsept kerakmi? | Do I need a prescription? | Мне=я.P нужен=нужный.A рецепт.N
Запишите меня к врачу | Маро ба қабули духтур навис кунед | Meni shifokorga yozib qoʻying | Book me in with the doctor | Запишите=записать.V меня=я.P к.R врачу=врач.N
Где можно сдать анализы? | Таҳлилҳоро дар куҷо супоридан мумкин? | Tahlillarni qayerda topshirsa boʻladi? | Where can I get tested? | Где.D можно.O сдать.V анализы=анализ.N
Я беременна | Ман ҳомиладор ҳастам | Men homiladorman | I am pregnant | Я.P беременна=беременная,беременный.A
Ребёнок заболел | Кӯдак бемор шуд | Bola kasal boʻldi | The child got sick | Ребёнок=ребёнок,ребенок.N заболел=заболеть.V
Мне уже лучше | Ҳолам беҳтар шуд | Oʻzimni yaxshiroq his qilyapman | I feel better already | Мне=я.P уже.D лучше=лучше,хорошо.D
Я плохо сплю | Ман бад хоб мекунам | Yomon uxlayapman | I sleep badly | Я.P плохо.D сплю=спать.V
Болит здесь | Ин ҷо дард мекунад | Shu yer ogʻriyapti | It hurts here | Болит=болеть.V здесь.D
У меня есть страховка | Ман суғурта дорам | Sugʻurtam bor | I have insurance | У.R меня=я.P есть.V страховка.N
Мне нужен больничный | Ба ман варақаи беморӣ лозим | Menga kasallik varaqasi kerak | I need a sick note | Мне=я.P нужен=нужный.A больничный.N
Я порезал палец | Ман ангуштамро буридам | Barmogʻimni kesib oldim | I cut my finger | Я.P порезал=порезать.V палец.N
Я упал | Ман афтодам | Yiqilib tushdim | I fell | Я.P упал=упасть.V
У меня кружится голова | Сарам чарх мезанад | Boshim aylanyapti | I feel dizzy | У.R меня=я.P кружится=кружиться.V голова.N
Мне трудно дышать | Нафас кашидан барои ман душвор аст | Nafas olishim qiyin | It's hard for me to breathe | Мне=я.P трудно.D дышать.V
Я принимаю таблетки | Ман ҳаб истеъмол мекунам | Tabletka ichyapman | I take pills | Я.P принимаю=принимать.V таблетки=таблетка.N
Нужно отдохнуть | Истироҳат кардан лозим | Dam olish kerak | You need to rest | Нужно.O отдохнуть.V
Сколько раз в день? | Рӯзе чанд маротиба? | Kuniga necha marta? | How many times a day? | Сколько.D раз.N в.R день.N
Я не курю | Ман тамоку намекашам | Men chekmayman | I don't smoke | Я.P не.O курю=курить.V
Береги себя | Худатро эҳтиёт кун | Oʻzingni asra | Take care of yourself | Береги=беречь.V себя.P
Выздоравливай скорее | Зудтар сиҳат шав | Tezroq tuzal | Get well soon | Выздоравливай=выздоравливать.V скорее=скоро.D
Мне нужно к стоматологу | Ба ман ба назди дандонпизишк рафтан лозим | Tish shifokoriga borishim kerak | I need to see a dentist | Мне=я.P нужно.O к.R стоматологу=стоматолог.N

# Дом и семья
Я дома | Ман дар хонаам | Uydaman | I'm at home | Я.P дома.D
Мама дома? | Модар дар хона аст? | Onam uydami? | Is mom at home? | Мама.N дома.D
Я скучаю по семье | Ман ба оилаам дилтанг шудам | Oilamni sogʻindim | I miss my family | Я.P скучаю=скучать.V по.R семье=семья.N
Как твоя семья? | Оилаат чӣ хел? | Oilang qalay? | How is your family? | Как.D твоя=твой.P семья.N
У меня большая семья | Ман оилаи калон дорам | Oilam katta | I have a big family | У.R меня=я.P большая=большой.A семья.N
Моя мама болеет | Модарам бемор аст | Onam kasal | My mom is sick | Моя=мой.P мама.N болеет=болеть.V
Я позвоню родителям | Ман ба падару модарам занг мезанам | Ota-onamga qoʻngʻiroq qilaman | I'll call my parents | Я.P позвоню=позвонить.V родителям=родители,родитель.N
Мой отец работает здесь | Падари ман дар ин ҷо кор мекунад | Otam shu yerda ishlaydi | My father works here | Мой.P отец.N работает=работать.V здесь.D
Я снимаю квартиру | Ман хона иҷора гирифтаам | Kvartira ijaraga olganman | I rent an apartment | Я.P снимаю=снимать.V квартиру=квартира.N
Сколько стоит аренда? | Иҷора чанд пул аст? | Ijara qancha turadi? | How much is the rent? | Сколько.D стоит=стоить.V аренда.N
Квартира свободна? | Хона холӣ аст? | Kvartira boʻshmi? | Is the apartment available? | Квартира.N свободна=свободный.A
Нет горячей воды | Оби гарм нест | Issiq suv yoʻq | There's no hot water | Нет.O горячей=горячий.A воды=вода.N
Свет не работает | Барқ кор намекунад | Chiroq ishlamayapti | The light doesn't work | Свет.N не.O работает=работать.V
Кран течёт | Кран мечакад | Jumrak oqyapti | The tap is leaking | Кран.N течёт=течь.V
Закрой дверь | Дарро пӯш | Eshikni yop | Close the door | Закрой=закрыть.V дверь.N
Открой окно | Тирезаро кушо | Derazani och | Open the window | Открой=открыть.V окно.N
Здесь холодно | Ин ҷо хунук аст | Bu yer sovuq | It's cold here | Здесь.D холодно.D
Включи свет | Чароғро даргирон | Chiroqni yoq | Turn on the light | Включи=включить.V свет.N
Выключи телевизор | Телевизорро хомӯш кун | Televizorni oʻchir | Turn off the TV | Выключи=выключить.V телевизор.N
Где ключи? | Калидҳо дар куҷоянд? | Kalitlar qayerda? | Where are the keys? | Где.D ключи=ключ.N
Я потерял ключи | Ман калидҳоро гум кардам | Kalitlarni yoʻqotdim | I lost the keys | Я.P потерял=потерять.V ключи=ключ.N
Я убираю квартиру | Ман хонаро тоза мекунам | Uyni yigʻishtiryapman | I'm cleaning the apartment | Я.P убираю=убирать.V квартиру=квартира.N
Нужно постирать одежду | Либосҳоро шустан лозим | Kiyimlarni yuvish kerak | I need to do the laundry | Нужно.O постирать.V одежду=одежда.N
Приходи в гости | Ба меҳмонӣ биё | Mehmonga kel | Come and visit | Приходи=приходить.V в.R гости=гость.N
Заходи, садись | Даро, нишин | Kir, oʻtir | Come in, sit down | Заходи=заходить.V садись=садиться.V
Чувствуй себя как дома | Худро мисли дар хона ҳис кун | Oʻzingni uydagidek his qil | Make yourself at home | Чувствуй=чувствовать.V себя.P как.D дома.D
Мои дети уже спят | Фарзандонам аллакай хобанд | Bolalarim allaqachon uxlashyapti | My children are already asleep | Мои=мой.P дети=ребёнок,ребенок,дети.N уже.D спят=спать.V
Сын вырос | Писар калон шуд | Oʻgʻlim katta boʻldi | My son has grown up | Сын.N вырос=вырасти.V
Моя дочь учится | Духтарам мехонад | Qizim oʻqiydi | My daughter studies | Моя=мой.P дочь.N учится=учиться.V
Бабушка живёт в деревне | Бибӣ дар деҳа зиндагӣ мекунад | Buvim qishloqda yashaydi | Grandma lives in a village | Бабушка.N живёт=жить.V в.R деревне=деревня.N
Я женюсь летом | Ман тобистон хонадор мешавам | Yozda uylanaman | I'm getting married in summer | Я.P женюсь=жениться.V летом.D
У нас родился сын | Мо писардор шудем | Bizda oʻgʻil tugʻildi | We had a son | У.R нас=мы.P родился=родиться.V сын.N
Соседи шумят | Ҳамсояҳо ғавғо мекунанд | Qoʻshnilar shovqin qilyapti | The neighbors are noisy | Соседи=сосед.N шумят=шуметь.V
Пора спать | Вақти хоб аст | Uxlash vaqti | Time to sleep | Пора.O спать.V
Я приготовлю ужин | Ман шом тайёр мекунам | Kechki ovqat tayyorlayman | I'll make dinner | Я.P приготовлю=приготовить.V ужин.N

# Еда
Я хочу есть | Ман гурусна ҳастам | Ovqat yegim kelyapti | I'm hungry | Я.P хочу=хотеть.V есть.V
Я хочу пить | Ман ташна ҳастам | Chanqadim | I'm thirsty | Я.P хочу=хотеть.V пить.V
Можно воды? | Об мумкин? | Suv bersangiz? | Can I have some water? | Можно.O воды=вода.N
Что будешь есть? | Чӣ мехӯрӣ? | Nima yeysan? | What will you eat? | Что.O будешь=быть.V есть.V
Меню, пожалуйста | Меню, лутфан | Menyu, iltimos | The menu, please | Меню.N пожалуйста.O
Счёт, пожалуйста | Ҳисоб, лутфан | Hisob, iltimos | The bill, please | Счёт=счёт,счет.N пожалуйста.O
Это очень вкусно | Ин хеле болаззат аст | Bu juda mazali | This is very tasty | Это.O очень.D вкусно.D
Я не ем свинину | Ман гӯшти хук намехӯрам | Men choʻchqa goʻshtini yemayman | I don't eat pork | Я.P не.O ем=есть,кушать.V свинину=свинина.N
Здесь есть халяльная еда? | Ин ҷо хӯроки ҳалол ҳаст? | Bu yerda halol ovqat bormi? | Is there halal food here? | Здесь.D есть.V халяльная=халяльный.A еда.N
Я сыт | Ман сер шудам | Toʻydim | I'm full | Я.P сыт=сытый.A
Без сахара, пожалуйста | Бе шакар, лутфан | Shakarsiz, iltimos | Without sugar, please | Без.R сахара=сахар.N пожалуйста.O
Ещё чаю? | Боз чой? | Yana choy? | More tea? | Ещё=ещё,еще.D чаю=чай.N
Давай пообедаем вместе | Биё якҷоя хӯроки нисфирӯзӣ хӯрем | Keling, birga tushlik qilaylik | Let's have lunch together | Давай=давать.V пообедаем=пообедать.V вместе.D
Я завтракаю дома | Ман дар хона наҳорӣ мекунам | Uyda nonushta qilaman | I have breakfast at home | Я.P завтракаю=завтракать.V дома.D
Это острое? | Ин тунд аст? | Bu achchiqmi? | Is it spicy? | Это.O острое=острый.A
Суп холодный | Шӯрбо хунук аст | Shoʻrva sovuq | The soup is cold | Суп.N холодный.A
Я на диете | Ман парҳез дорам | Parhezdaman | I'm on a diet | Я.P на.R диете=диета.N
Где можно поесть? | Дар куҷо хӯрок хӯрдан мумкин? | Qayerda ovqatlansa boʻladi? | Where can I eat? | Где.D можно.O поесть.V
Мне то же самое | Ба ман ҳам ҳамон | Menga ham xuddi shunday | The same for me | Мне=я.P то.O же.O самое=самый.A
Я сам приготовил | Худам тайёр кардам | Oʻzim tayyorladim | I cooked it myself | Я.P сам.P приготовил=приготовить.V
Положите с собой | Барои бурдан бастабандӣ кунед | Olib ketishga solib bering | To go, please | Положите=положить.V с.R собой=себя.P
Мясо готово | Гӯшт тайёр аст | Goʻsht tayyor | The meat is ready | Мясо.N готово=готовый.A
Попробуй это | Инро бичаш | Buni tatib koʻr | Try this | Попробуй=попробовать.V это.O
Я не пью алкоголь | Ман машрубот наменӯшам | Men spirtli ichimlik ichmayman | I don't drink alcohol | Я.P не.O пью=пить.V алкоголь.N
Налей мне чаю | Ба ман чой рез | Menga choy quy | Pour me some tea | Налей=налить.V мне=я.P чаю=чай.N
Кофе с молоком | Қаҳва бо шир | Sutli qahva | Coffee with milk | Кофе.N с.R молоком=молоко.N
Еда остыла | Хӯрок хунук шуд | Ovqat sovib qoldi | The food got cold | Еда.N остыла=остыть.V
Купи хлеба по дороге | Дар роҳ нон харида биё | Yoʻlda non olib kel | Buy bread on the way | Купи=купить.V хлеба=хлеб.N по.R дороге=дорога.N
Я угощаю | Ман пул медиҳам | Men mehmon qilaman | It's my treat | Я.P угощаю=угощать.V
Спасибо, было вкусно | Ташаккур, болаззат буд | Rahmat, mazali boʻldi | Thanks, it was delicious | Спасибо.O было=быть.V вкусно.D

# Время и планы
Я приду через час | Ман пас аз як соат меоям | Bir soatdan keyin kelaman | I'll come in an hour | Я.P приду=прийти.V через.R час.N
Подожди минуту | Як дақиқа сабр кун | Bir daqiqa kut | Wait a minute | Подожди=подождать.V минуту=минута.N
Я скоро буду | Ман ба зудӣ мерасам | Tez orada yetib boraman | I'll be there soon | Я.P скоро.D буду=быть.V
Что ты делаешь вечером? | Бегоҳ чӣ кор мекунӣ? | Kechqurun nima qilasan? | What are you doing tonight? | Что.O ты.P делаешь=делать.V вечером.D
Давай встретимся завтра | Биё фардо вохӯрем | Keling, ertaga uchrashaylik | Let's meet tomorrow | Давай=давать.V встретимся=встретиться.V завтра.D
Где встретимся? | Дар куҷо вохӯрем? | Qayerda uchrashamiz? | Where shall we meet? | Где.D встретимся=встретиться.V
Во сколько? | Соати чанд? | Soat nechada? | At what time? | Во=в.R сколько.D
Я занят сегодня | Ман имрӯз банд ҳастам | Bugun bandman | I'm busy today | Я.P занят=занятый.A сегодня.D
Давай в другой раз | Биё дафъаи дигар | Keling, boshqa safar | Let's do it another time | Давай=давать.V в.R другой.A раз.N
У меня нет времени | Ман вақт надорам | Vaqtim yoʻq | I have no time | У.R меня=я.P нет.O времени=время.N
Я уезжаю в пятницу | Ман рӯзи ҷумъа меравам | Juma kuni ketaman | I'm leaving on Friday | Я.P уезжаю=уезжать.V в.R пятницу=пятница.N
Какой сегодня день? | Имрӯз чӣ рӯз аст? | Bugun qanday kun? | What day is it today? | Какой.A сегодня.D день.N
Сегодня понедельник | Имрӯз душанбе аст | Bugun dushanba | Today is Monday | Сегодня.D понедельник.N
Вчера было холодно | Дирӯз хунук буд | Kecha sovuq edi | It was cold yesterday | Вчера.D было=быть.V холодно.D
Я вернусь вечером | Ман бегоҳ бармегардам | Kechqurun qaytaman | I'll be back in the evening | Я.P вернусь=вернуться.V вечером.D
Мы опоздаем | Мо дер мемонем | Kechikamiz | We'll be late | Мы.P опоздаем=опоздать.V
Не опаздывай | Дер накун | Kechikma | Don't be late | Не.O опаздывай=опаздывать.V
Уже поздно | Аллакай дер шуд | Allaqachon kech | It's already late | Уже.D поздно.D
Ещё рано | Ҳоло барвақт аст | Hali erta | It's still early | Ещё=ещё,еще.D рано.D
Я встаю в шесть | Ман соати шаш мехезам | Soat oltida turaman | I get up at six | Я.P встаю=вставать.V в.R шесть.U
Когда ты освободишься? | Ту кай холӣ мешавӣ? | Qachon boʻshaysan? | When will you be free? | Когда.D ты.P освободишься=освободиться.V
Летом я поеду домой | Тобистон ман ба ватан меравам | Yozda uyga boraman | In summer I'll go home | Летом.D я.P поеду=поехать.V домой.D
Я здесь уже год | Ман аллакай як сол боз дар ин ҷо ҳастам | Bu yerda bir yildan beri yashayman | I've been here for a year | Я.P здесь.D уже.D год.N
Время летит быстро | Вақт зуд мегузарад | Vaqt tez oʻtadi | Time flies | Время.N летит=лететь.V быстро.D
Я планирую остаться | Ман нақша дорам, ки бимонам | Qolishni rejalashtiryapman | I plan to stay | Я.P планирую=планировать.V остаться.V
Перенесём на завтра | Ба фардо мегузаронем | Ertaga koʻchiramiz | Let's move it to tomorrow | Перенесём=перенести.V на.R завтра.D
Я успею | Ман ба вақт мерасам | Ulguraman | I'll make it in time | Я.P успею=успеть.V
Я свободен в субботу | Ман рӯзи шанбе холӣ ҳастам | Shanba kuni boʻshman | I'm free on Saturday | Я.P свободен=свободный.A в.R субботу=суббота.N
Через неделю | Пас аз як ҳафта | Bir haftadan keyin | In a week | Через.R неделю=неделя.N
В следующем месяце | Дар моҳи оянда | Kelasi oyda | Next month | В.R следующем=следующий.A месяце=месяц.N
Это займёт час | Ин як соат вақт мегирад | Bu bir soat oladi | It will take an hour | Это.O займёт=занять.V час.N
Я жду уже долго | Ман кайҳо боз интизорам | Anchadan beri kutyapman | I've been waiting a long time | Я.P жду=ждать.V уже.D долго.D
Мы всё успели | Мо ҳама корро ба вақт кардем | Hammasiga ulgurdik | We made it in time | Мы.P всё=всё,весь.O успели=успеть.V

# Телефон и связь
Позвони мне | Ба ман занг зан | Menga qoʻngʻiroq qil | Call me | Позвони=позвонить.V мне=я.P
Я тебе перезвоню | Ман ба ту боз занг мезанам | Senga qayta qoʻngʻiroq qilaman | I'll call you back | Я.P тебе=ты.P перезвоню=перезвонить.V
Какой у тебя номер? | Рақами ту чанд аст? | Raqaming qanaqa? | What's your number? | Какой.A у.R тебя=ты.P номер.N
Напиши мне сообщение | Ба ман паём навис | Menga xabar yoz | Send me a message | Напиши=написать.V мне=я.P сообщение.N
Я не слышу тебя | Ман туро намешунавам | Seni eshitmayapman | I can't hear you | Я.P не.O слышу=слышать.V тебя=ты.P
Плохая связь | Алоқа бад аст | Aloqa yomon | Bad connection | Плохая=плохой.A связь.N
У меня сел телефон | Телефонам хомӯш шуд | Telefonim oʻchib qoldi | My phone died | У.R меня=я.P сел=сесть.V телефон.N
Где можно зарядить телефон? | Телефонро дар куҷо заряд кардан мумкин? | Telefonni qayerda zaryadlasa boʻladi? | Where can I charge my phone? | Где.D можно.O зарядить.V телефон.N
Есть интернет? | Интернет ҳаст? | Internet bormi? | Is there internet? | Есть.V интернет.N
Интернет не работает | Интернет кор намекунад | Internet ishlamayapti | The internet doesn't work | Интернет.N не.O работает=работать.V
Какой пароль? | Рамз чист? | Parol qanaqa? | What's the password? | Какой.A пароль.N
Отправь мне фото | Ба ман акс фирист | Menga rasm yubor | Send me a photo | Отправь=отправить.V мне=я.P фото.N
Я получил твоё сообщение | Ман паёми туро гирифтам | Xabaringni oldim | I got your message | Я.P получил=получить.V твоё=твой.P сообщение.N
Кто звонил? | Кӣ занг зад? | Kim qoʻngʻiroq qildi? | Who called? | Кто.O звонил=звонить.V
Не могу говорить | Гап зада наметавонам | Gaplasha olmayman | I can't talk now | Не.O могу=мочь.V говорить.V
Я за рулём | Ман мошин ронда истодаам | Rul ortidaman | I'm driving | Я.P за.R рулём=руль.N
Положи деньги на телефон | Ба телефон пул гузор | Telefonga pul sol | Top up the phone | Положи=положить.V деньги.N на.R телефон.N
Скачай это приложение | Ин барномаро боргирӣ кун | Bu ilovani yuklab ol | Download this app | Скачай=скачать.V это.O приложение.N
Включи громкую связь | Овозбаландкунакро даргирон | Karnayni yoq | Turn on speakerphone | Включи=включить.V громкую=громкий.A связь.N
Абонент недоступен | Муштарӣ дастрас нест | Abonent mavjud emas | The subscriber is unavailable | Абонент.N недоступен=недоступный.A
Я жду твоего звонка | Ман занги туро интизорам | Qoʻngʻirogʻingni kutaman | I'm waiting for your call | Я.P жду=ждать.V твоего=твой.P звонка=звонок.N
Напомни мне завтра | Фардо ба ман ёдрас кун | Ertaga eslatib qoʻy | Remind me tomorrow | Напомни=напомнить.V мне=я.P завтра.D
Скинь адрес | Суроғаро фирист | Manzilni tashla | Send me the address | Скинь=скинуть.V адрес.N
Я на связи | Ман дар тамос ҳастам | Aloqadaman | I'm reachable | Я.P на.R связи=связь.N

# Чувства и мнения
Я рад | Ман шодам | Xursandman | I'm glad | Я.P рад=рад,радый.A
Мне грустно | Ман ғамгинам | Xafaman | I'm sad | Мне=я.P грустно.D
Мне скучно | Дилам танг шуд | Zerikdim | I'm bored | Мне=я.P скучно.D
Мне страшно | Ман метарсам | Qoʻrqyapman | I'm scared | Мне=я.P страшно.D
Я волнуюсь | Ман ташвиш мекашам | Hayajonlanyapman | I'm nervous | Я.P волнуюсь=волноваться.V
Я злюсь | Ман хашмгинам | Jahlim chiqyapti | I'm angry | Я.P злюсь=злиться.V
Мне нравится здесь | Ин ҷо ба ман маъқул аст | Bu yer menga yoqadi | I like it here | Мне=я.P нравится=нравиться.V здесь.D
Мне не нравится это | Ин ба ман маъқул нест | Bu menga yoqmaydi | I don't like this | Мне=я.P не.O нравится=нравиться.V это.O
Я тебя люблю | Ман туро дӯст медорам | Men seni sevaman | I love you | Я.P тебя=ты.P люблю=любить.V
Я люблю свою работу | Ман кори худро дӯст медорам | Ishimni yaxshi koʻraman | I love my job | Я.P люблю=любить.V свою=свой.P работу=работа.N
Я думаю, да | Ба фикрам, ҳа | Menimcha, ha | I think so | Я.P думаю=думать.V да.O
Я так не думаю | Ман ин тавр фикр намекунам | Men bunday deb oʻylamayman | I don't think so | Я.P так.D не.O думаю=думать.V
Это хорошая идея | Ин фикри хуб аст | Bu yaxshi gʻoya | That's a good idea | Это.O хорошая=хороший.A идея.N
Это интересно | Ин ҷолиб аст | Bu qiziq | That's interesting | Это.O интересно.D
Это неважно | Ин муҳим нест | Bu muhim emas | It doesn't matter | Это.O неважно.D
Это очень важно | Ин хеле муҳим аст | Bu juda muhim | This is very important | Это.O очень.D важно.D
Мне всё равно | Ба ман фарқ надорад | Menga baribir | I don't care | Мне=я.P всё=всё,весь.O равно.D
Я горжусь тобой | Ман бо ту фахр мекунам | Sen bilan faxrlanaman | I'm proud of you | Я.P горжусь=гордиться.V тобой=ты.P
Я счастлив | Ман хушбахтам | Men baxtliman | I'm happy | Я.P счастлив=счастливый.A
Не переживай | Ғам нахӯр | Qaygʻurma | Don't worry | Не.O переживай=переживать.V
Всё будет хорошо | Ҳамааш хуб мешавад | Hammasi yaxshi boʻladi | Everything will be fine | Всё=всё,весь.O будет=быть.V хорошо.D
Я в шоке | Ман дар ҳайратам | Hayratdaman | I'm shocked | Я.P в.R шоке=шок.N
Как жаль | Чӣ афсӯс | Qanday achinarli | What a pity | Как.D жаль.O
Мне стыдно | Ман шарм дорам | Uyalaman | I'm ashamed | Мне=я.P стыдно.D
Я тебе верю | Ман ба ту бовар мекунам | Senga ishonaman | I believe you | Я.P тебе=ты.P верю=верить.V
Ты прав | Ту ҳақ ҳастӣ | Sen haqsan | You're right | Ты.P прав=правый.A
Мне кажется, он врёт | Ба назарам, вай дурӯғ мегӯяд | Menimcha, u yolgʻon gapiryapti | I think he's lying | Мне=я.P кажется=казаться.V он.P врёт=врать.V
Это смешно | Ин хандаовар аст | Bu kulgili | That's funny | Это.O смешно.D
Я обиделся | Ман ранҷидам | Xafa boʻldim | I'm offended | Я.P обиделся=обидеться.V
Не обижайся | Наранҷ | Xafa boʻlma | Don't be offended | Не.O обижайся=обижаться.V
Мне жарко | Ба ман гарм аст | Menga issiq | I'm hot | Мне=я.P жарко.D
Я соскучился по тебе | Ман ба ту дилтанг шудам | Seni sogʻindim | I missed you | Я.P соскучился=соскучиться.V по.R тебе=ты.P
Ты молодец | Офарин ба ту | Barakalla | Well done | Ты.P молодец.N
Какой красивый город | Чӣ шаҳри зебо | Qanday chiroyli shahar | What a beautiful city | Какой.A красивый.A город.N
Я надеюсь на тебя | Ман ба ту умед дорам | Senga umid qilaman | I'm counting on you | Я.P надеюсь=надеяться.V на.R тебя=ты.P

# Согласие, отказ, просьбы
Да, конечно | Ҳа, албатта | Ha, albatta | Yes, of course | Да.O конечно.D
Нет, спасибо | Не, ташаккур | Yoʻq, rahmat | No, thank you | Нет.O спасибо.O
Я согласен | Ман розӣ ҳастам | Roziman | I agree | Я.P согласен=согласный.A
Хорошо, договорились | Хуб, ба мувофиқа расидем | Yaxshi, kelishdik | Okay, it's a deal | Хорошо.D договорились=договориться.V
Давай попробуем | Биё кӯшиш кунем | Keling, urinib koʻramiz | Let's try | Давай=давать.V попробуем=попробовать.V
Я не могу | Ман наметавонам | Qila olmayman | I can't | Я.P не.O могу=мочь.V
Я постараюсь | Ман кӯшиш мекунам | Harakat qilaman | I'll try | Я.P постараюсь=постараться.V
Можешь помочь? | Ёрӣ дода метавонӣ? | Yordam bera olasanmi? | Can you help? | Можешь=мочь.V помочь.V
Помоги мне, пожалуйста | Лутфан, ба ман ёрӣ деҳ | Iltimos, menga yordam ber | Help me, please | Помоги=помочь.V мне=я.P пожалуйста.O
Подожди меня | Маро интизор шав | Meni kut | Wait for me | Подожди=подождать.V меня=я.P
Не надо | Лозим нест | Kerak emas | No need | Не.O надо.O
Хватит уже | Бас аст дигар | Yetar endi | That's enough | Хватит=хватить,хватать.V уже.D
Как хочешь | Чӣ хел ки мехоҳӣ | Xohlaganingdek | As you wish | Как.D хочешь=хотеть.V
Я не против | Ман зид нестам | Men qarshi emasman | I don't mind | Я.P не.O против.R
Можно мне тоже? | Ба ман ҳам мумкин? | Menga ham boʻladimi? | Can I have one too? | Можно.O мне=я.P тоже.D
Передай соль | Намакро деҳ | Tuzni uzat | Pass the salt | Передай=передать.V соль.N
Принеси воды | Об биёр | Suv olib kel | Bring some water | Принеси=принести.V воды=вода.N
Сделай потише | Пасттар кун | Pastroq qil | Turn it down | Сделай=сделать.V потише=тихо.D
Помолчи, пожалуйста | Лутфан, хомӯш шав | Iltimos, jim tur | Please be quiet | Помолчи=помолчать.V пожалуйста.O
Конечно, можно | Албатта, мумкин | Albatta, mumkin | Of course you can | Конечно.D можно.O
Здесь нельзя курить | Ин ҷо тамокукашӣ манъ аст | Bu yerda chekish mumkin emas | No smoking here | Здесь.D нельзя.O курить.V
Это запрещено | Ин манъ аст | Bu taqiqlangan | It's forbidden | Это.O запрещено=запрещённый,запрещенный.A
Я подумаю | Ман фикр мекунам | Oʻylab koʻraman | I'll think about it | Я.P подумаю=подумать.V
Решай сам | Худат қарор деҳ | Oʻzing hal qil | Decide for yourself | Решай=решать.V сам.P
Не трогай | Даст назан | Tegma | Don't touch | Не.O трогай=трогать.V
Иди сюда | Ин ҷо биё | Bu yoqqa kel | Come here | Иди=идти.V сюда.D
Пойдём со мной | Бо ман биё | Men bilan yur | Come with me | Пойдём=пойти.V со=с.R мной=я.P
Возьми с собой | Бо худ гир | Oʻzing bilan ol | Take it with you | Возьми=взять.V с.R собой=себя.P
Отдай мне | Ба ман баргардон | Menga qaytar | Give it back to me | Отдай=отдать.V мне=я.P

# Помощь, документы, город
На помощь | Ёрӣ диҳед! | Yordam bering! | Help! | На.R помощь.N
Вызовите полицию | Полисро ҷеғ занед | Politsiyani chaqiring | Call the police | Вызовите=вызвать.V полицию=полиция.N
У меня украли телефон | Телефонамро дуздиданд | Telefonimni oʻgʻirlashdi | My phone was stolen | У.R меня=я.P украли=украсть.V телефон.N
Я потерял паспорт | Ман шиносномаамро гум кардам | Pasportimni yoʻqotdim | I lost my passport | Я.P потерял=потерять.V паспорт.N
Где посольство? | Сафорат дар куҷост? | Elchixona qayerda? | Where is the embassy? | Где.D посольство.N
Покажите документы | Ҳуҷҷатҳоро нишон диҳед | Hujjatlarni koʻrsating | Show your documents | Покажите=показать.V документы=документ.N
Вот мой паспорт | Ана шиносномаи ман | Mana pasportim | Here is my passport | Вот.O мой.P паспорт.N
Мне нужна регистрация | Ба ман бақайдгирӣ лозим | Menga roʻyxatdan oʻtish kerak | I need registration | Мне=я.P нужна=нужный.A регистрация.N
Где сделать патент? | Патентро дар куҷо гирифтан мумкин? | Patentni qayerda olsa boʻladi? | Where do I get a work patent? | Где.D сделать.V патент.N
Мой патент закончился | Мӯҳлати патенти ман гузашт | Patentimning muddati tugadi | My patent has expired | Мой.P патент.N закончился=закончиться.V
Я не виноват | Ман гунаҳкор нестам | Men aybdor emasman | It's not my fault | Я.P не.O виноват=виноватый.A
Мне нужен переводчик | Ба ман тарҷумон лозим | Menga tarjimon kerak | I need an interpreter | Мне=я.P нужен=нужный.A переводчик.N
Где здесь банк? | Бонк дар куҷост? | Bu yerda bank qayerda? | Where is a bank here? | Где.D здесь.D банк.N
Здесь пожар | Ин ҷо сӯхтор аст | Bu yerda yongʻin | There's a fire here | Здесь.D пожар.N
Осторожно, машина | Эҳтиёт, мошин | Ehtiyot boʻl, mashina | Watch out, a car | Осторожно.D машина.N
Мне нужна помощь | Ба ман ёрӣ лозим | Menga yordam kerak | I need help | Мне=я.P нужна=нужный.A помощь.N
Это срочно | Ин фаврӣ аст | Bu shoshilinch | It's urgent | Это.O срочно.D
Где ближайший магазин? | Мағозаи наздиктарин дар куҷост? | Eng yaqin doʻkon qayerda? | Where is the nearest shop? | Где.D ближайший.A магазин.N
Какой здесь адрес? | Суроғаи ин ҷо чист? | Bu yerning manzili qanday? | What's the address here? | Какой.A здесь.D адрес.N
Я ищу эту улицу | Ман ин кӯчаро меҷӯям | Bu koʻchani qidiryapman | I'm looking for this street | Я.P ищу=искать.V эту=этот.P улицу=улица.N
Где находится почта? | Почта дар куҷо ҷойгир аст? | Pochta qayerda joylashgan? | Where is the post office? | Где.D находится=находиться.V почта.N
Здесь можно фотографировать? | Ин ҷо акс гирифтан мумкин? | Bu yerda suratga olish mumkinmi? | Can I take photos here? | Здесь.D можно.O фотографировать.V
Где можно помыть руки? | Дастҳоро дар куҷо шустан мумкин? | Qoʻlni qayerda yuvsa boʻladi? | Where can I wash my hands? | Где.D можно.O помыть.V руки=рука.N
Где можно помолиться? | Дар куҷо намоз хондан мумкин? | Qayerda namoz oʻqisa boʻladi? | Where can I pray? | Где.D можно.O помолиться.V
Где ближайшая мечеть? | Масҷиди наздиктарин дар куҷост? | Eng yaqin masjid qayerda? | Where is the nearest mosque? | Где.D ближайшая=ближайший.A мечеть.N
Мне нужен юрист | Ба ман ҳуқуқшинос лозим | Menga yurist kerak | I need a lawyer | Мне=я.P нужен=нужный.A юрист.N
Я буду жаловаться | Ман шикоят мекунам | Shikoyat qilaman | I'll file a complaint | Я.P буду=быть.V жаловаться.V
Меня обманули | Маро фиреб доданд | Meni aldashdi | I was cheated | Меня=я.P обманули=обмануть.V
Отпустите меня | Маро сар диҳед | Meni qoʻyib yuboring | Let me go | Отпустите=отпустить.V меня=я.P
Где отделение полиции? | Шӯъбаи полис дар куҷост? | Politsiya boʻlimi qayerda? | Where is the police station? | Где.D отделение.N полиции=полиция.N
Как оформить документы? | Ҳуҷҷатҳоро чӣ хел ба расмият дарорам? | Hujjatlarni qanday rasmiylashtirish kerak? | How do I process the documents? | Как.D оформить.V документы=документ.N
Какие документы нужны? | Кадом ҳуҷҷатҳо лозиманд? | Qanday hujjatlar kerak? | What documents are needed? | Какие=какой.A документы=документ.N нужны=нужный.A
Где заполнить анкету? | Анкетаро дар куҷо пур кунам? | Anketani qayerda toʻldiraman? | Where do I fill in the form? | Где.D заполнить.V анкету=анкета.N
Распишитесь здесь | Ин ҷо имзо гузоред | Shu yerga imzo qoʻying | Sign here | Распишитесь=расписаться.V здесь.D
Сделайте копию | Нусха бардоред | Nusxa koʻchiring | Make a copy | Сделайте=сделать.V копию=копия.N
Очередь большая? | Навбат калон аст? | Navbat kattami? | Is the line long? | Очередь.N большая=большой.A
Кто последний? | Охирин кист? | Oxirgi kim? | Who's last in line? | Кто.O последний.A
Я стою в очереди | Ман дар навбат истодаам | Navbatda turibman | I'm standing in line | Я.P стою=стоять.V в.R очереди=очередь.N
Окно номер три | Тирезаи рақами се | Uchinchi oyna | Window number three | Окно.N номер.N три.U

# Погода, город, досуг
Какая сегодня погода? | Имрӯз ҳаво чӣ хел аст? | Bugun havo qanday? | What's the weather today? | Какая=какой.A сегодня.D погода.N
Идёт дождь | Борон меборад | Yomgʻir yogʻyapti | It's raining | Идёт=идти.V дождь.N
Идёт снег | Барф меборад | Qor yogʻyapti | It's snowing | Идёт=идти.V снег.N
На улице тепло | Дар берун гарм аст | Tashqarida iliq | It's warm outside | На.R улице=улица.N тепло.D
Сегодня очень жарко | Имрӯз хеле гарм аст | Bugun juda issiq | It's very hot today | Сегодня.D очень.D жарко.D
Возьми зонт | Чатрро гир | Soyabonni ol | Take an umbrella | Возьми=взять.V зонт.N
Оденься теплее | Гармтар пӯш | Issiqroq kiyin | Dress warmer | Оденься=одеться.V теплее=тепло.D
Пойдём гулять | Биё сайр кунем | Yur, sayr qilamiz | Let's go for a walk | Пойдём=пойти.V гулять.V
Что будем делать? | Чӣ кор мекунем? | Nima qilamiz? | What shall we do? | Что.O будем=быть.V делать.V
Давай посмотрим фильм | Биё филм тамошо кунем | Keling, kino koʻramiz | Let's watch a movie | Давай=давать.V посмотрим=посмотреть.V фильм.N
Я люблю футбол | Ман футболро дӯст медорам | Men futbolni yaxshi koʻraman | I love football | Я.P люблю=любить.V футбол.N
Ты играешь в футбол? | Ту футбол бозӣ мекунӣ? | Futbol oʻynaysanmi? | Do you play football? | Ты.P играешь=играть.V в.R футбол.N
Где здесь парк? | Боғ дар куҷост? | Bu yerda park qayerda? | Where is a park here? | Где.D здесь.D парк.N
Я хожу в спортзал | Ман ба толори варзиш меравам | Sport zaliga boraman | I go to the gym | Я.P хожу=ходить.V в.R спортзал.N
Красивое место | Ҷои зебо | Chiroyli joy | A beautiful place | Красивое=красивый.A место.N
Город большой | Шаҳр калон аст | Shahar katta | The city is big | Город.N большой.A
Мне нравится этот город | Ин шаҳр ба ман маъқул аст | Bu shahar menga yoqadi | I like this city | Мне=я.P нравится=нравиться.V этот.P город.N
Я отдыхаю | Ман истироҳат мекунам | Dam olyapman | I'm resting | Я.P отдыхаю=отдыхать.V
Пойдём в кафе | Биё ба қаҳвахона равем | Kafega boraylik | Let's go to a café | Пойдём=пойти.V в.R кафе.N
Сфотографируй меня | Аз ман акс гир | Meni suratga ol | Take a photo of me | Сфотографируй=сфотографировать.V меня=я.P
Я слушаю музыку | Ман мусиқӣ гӯш мекунам | Musiqa tinglayapman | I'm listening to music | Я.P слушаю=слушать.V музыку=музыка.N
Во сколько начало? | Оғоз соати чанд аст? | Boshlanishi soat nechada? | What time does it start? | Во=в.R сколько.D начало.N
Билеты ещё есть? | Чиптаҳо ҳоло ҳастанд? | Chiptalar hali bormi? | Are there still tickets? | Билеты=билет.N ещё=ещё,еще.D есть.V
Я поеду на море | Ман ба баҳр меравам | Dengizga boraman | I'll go to the sea | Я.P поеду=поехать.V на.R море.N
Зимой здесь холодно | Зимистон ин ҷо хунук аст | Qishda bu yer sovuq | It's cold here in winter | Зимой.D здесь.D холодно.D
Весной здесь красиво | Баҳор ин ҷо зебо аст | Bahorda bu yer chiroyli | It's beautiful here in spring | Весной.D здесь.D красиво.D
Сегодня праздник | Имрӯз ид аст | Bugun bayram | Today is a holiday | Сегодня.D праздник.N
Поздравляю тебя | Туро табрик мекунам | Seni tabriklayman | Congratulations | Поздравляю=поздравлять.V тебя=ты.P
Пойдём на свадьбу | Биё ба тӯй равем | Toʻyga boraylik | Let's go to the wedding | Пойдём=пойти.V на.R свадьбу=свадьба.N
Я умею плавать | Ман шино карда метавонам | Suzishni bilaman | I can swim | Я.P умею=уметь.V плавать.V
Я не умею готовить | Ман пухтупаз карда наметавонам | Ovqat pishirishni bilmayman | I can't cook | Я.P не.O умею=уметь.V готовить.V
Какой у тебя любимый цвет? | Ранги дӯстдоштаи ту кадом аст? | Sevimli ranging qaysi? | What's your favorite color? | Какой.A у.R тебя=ты.P любимый.A цвет.N
Чем ты увлекаешься? | Ту ба чӣ шавқ дорӣ? | Nimaga qiziqasan? | What are your hobbies? | Чем=что.O ты.P увлекаешься=увлекаться.V
Я читаю новости | Ман хабарҳоро мехонам | Yangiliklarni oʻqiyman | I read the news | Я.P читаю=читать.V новости=новость.N
"""


def parse() -> list[dict]:
    """Every phrase gets the template of its section («Знакомство и о себе»…):
    17 topic blocks instead of one template per role pattern."""
    phrases = []
    section = "Набор 500"
    for line in DATA.strip().splitlines():
        line = line.strip()
        if line.startswith("#"):
            section = line.lstrip("# ").strip()
            continue
        if not line:
            continue
        text, tg, uz, en, spec = (x.strip() for x in line.split(" | "))
        parts = []
        for token in spec.split():
            body, role = token.rsplit(".", 1)
            written, _, bases = body.partition("=")
            parts.append((written, [b.strip() for b in (bases or written.lower()).split(",")], ROLES[role]))
        phrases.append({"text": text, "tg": tg, "uz": uz, "en": en, "parts": parts, "template": section})
    return phrases
