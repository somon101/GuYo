"""A starter set of mini-phrases and templates for the Russian dictionary.

Each phrase is described by its parts: how the part reads in the phrase,
which dictionary word(s) it can belong to (the first one found is used)
and the role that word gets if it has none yet. Nothing here creates a
word: a phrase whose word isn't in the dictionary is skipped and reported,
so the admin can add the word and fill again. A missing FORM of an existing
word ("иду" of "идти") is added. Idempotent: a phrase that already exists
(same text) is left alone, and roles the admin set are never overwritten.
"""

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.mini_phrases.service import normalize_answer
from app.models.dictionary import Dictionary
from app.models.mini_phrase import MiniPhrase, MiniPhrasePart, MiniPhraseTemplate
from app.models.word import Word, WordForm

# --- Templates (explanations use part numbers, so the subject may be a
# pronoun or a noun alike) ----------------------------------------------------

WHO_ACTION = "Кто + действие"
WHO_ACTION_WHAT = "Кто + действие + что"
WHO_WHAT_KIND = "Кто/что + какой"

TEMPLATES: dict[str, dict] = {
    WHO_ACTION: {
        "explanation_ru": "Чтобы сказать «{translation}», сначала скажите, кто — {1} ({1.tr}), затем действие — {2} ({2.tr}). Получается: {phrase}",
        "explanation_tg": "Барои гуфтани «{translation}» аввал бигӯед, кӣ — {1} ({1.tr}), баъд амалро — {2} ({2.tr}). Натиҷа: {phrase}",
        "explanation_uz": "«{translation}» deyish uchun avval kimligini ayting — {1} ({1.tr}), keyin harakatni — {2} ({2.tr}). Natija: {phrase}",
    },
    WHO_ACTION_WHAT: {
        "explanation_ru": "Чтобы сказать «{translation}», скажите, кто — {1}, затем действие — {2} ({2.tr}), и в конце что — {3} ({3.tr}). Получается: {phrase}",
        "explanation_tg": "Барои гуфтани «{translation}» бигӯед, кӣ — {1}, баъд амалро — {2} ({2.tr}) ва дар охир чиро — {3} ({3.tr}). Натиҷа: {phrase}",
        "explanation_uz": "«{translation}» deyish uchun kimligini — {1}, keyin harakatni — {2} ({2.tr}), oxirida nimani — {3} ({3.tr}) ayting. Natija: {phrase}",
    },
    WHO_WHAT_KIND: {
        "explanation_ru": "Чтобы сказать «{translation}», назовите, кто или что — {1} ({1.tr}), и сразу добавьте, какой — {2} ({2.tr}). Слово «есть» по-русски здесь не говорят. Получается: {phrase}",
        "explanation_tg": "Барои гуфтани «{translation}» номбар кунед, кӣ ё чӣ — {1} ({1.tr}), ва фавран илова кунед, ки чӣ гуна — {2} ({2.tr}). Калимаи «аст» дар русӣ гуфта намешавад. Натиҷа: {phrase}",
        "explanation_uz": "«{translation}» deyish uchun kim yoki nimaligini ayting — {1} ({1.tr}), soʻng darhol qandayligini qoʻshing — {2} ({2.tr}). Rus tilida bu yerda «-dir» aytilmaydi. Natija: {phrase}",
    },
}

# --- Phrases -----------------------------------------------------------------
# (text, template, tg, uz, en, parts); a part is (text, [base words], role).

P = "pronoun"
V = "verb"
N = "noun"
A = "adjective"

STARTER: list[tuple] = [
    # Кто + действие
    ("Я иду", WHO_ACTION, "Ман меравам", "Men boraman", "I am going", [("Я", ["я"], P), ("иду", ["идти"], V)]),
    ("Ты идёшь", WHO_ACTION, "Ту меравӣ", "Sen borasan", "You are going", [("Ты", ["ты"], P), ("идёшь", ["идти"], V)]),
    ("Он идёт", WHO_ACTION, "Вай меравад", "U boradi", "He is going", [("Он", ["он"], P), ("идёт", ["идти"], V)]),
    ("Мы идём", WHO_ACTION, "Мо меравем", "Biz boramiz", "We are going", [("Мы", ["мы"], P), ("идём", ["идти"], V)]),
    ("Я ем", WHO_ACTION, "Ман мехӯрам", "Men yeyman", "I eat", [("Я", ["я"], P), ("ем", ["есть", "кушать"], V)]),
    ("Ты ешь", WHO_ACTION, "Ту мехӯрӣ", "Sen yeysan", "You eat", [("Ты", ["ты"], P), ("ешь", ["есть"], V)]),
    ("Я покушал", WHO_ACTION, "Ман хӯрок хӯрдам", "Men ovqatlandim", "I have eaten", [("Я", ["я"], P), ("покушал", ["покушать", "кушать"], V)]),
    ("Я сплю", WHO_ACTION, "Ман хоб мекунам", "Men uxlayman", "I am sleeping", [("Я", ["я"], P), ("сплю", ["спать"], V)]),
    ("Он спит", WHO_ACTION, "Вай хоб аст", "U uxlayapti", "He is sleeping", [("Он", ["он"], P), ("спит", ["спать"], V)]),
    ("Я работаю", WHO_ACTION, "Ман кор мекунам", "Men ishlayman", "I work", [("Я", ["я"], P), ("работаю", ["работать"], V)]),
    ("Она работает", WHO_ACTION, "Вай кор мекунад", "U ishlaydi", "She works", [("Она", ["она"], P), ("работает", ["работать"], V)]),
    ("Мы работаем", WHO_ACTION, "Мо кор мекунем", "Biz ishlaymiz", "We work", [("Мы", ["мы"], P), ("работаем", ["работать"], V)]),
    ("Я читаю", WHO_ACTION, "Ман мехонам", "Men oʻqiyman", "I am reading", [("Я", ["я"], P), ("читаю", ["читать"], V)]),
    ("Ты читаешь", WHO_ACTION, "Ту мехонӣ", "Sen oʻqiysan", "You are reading", [("Ты", ["ты"], P), ("читаешь", ["читать"], V)]),
    ("Я пишу", WHO_ACTION, "Ман менависам", "Men yozaman", "I am writing", [("Я", ["я"], P), ("пишу", ["писать"], V)]),
    ("Я говорю", WHO_ACTION, "Ман гап мезанам", "Men gapiraman", "I speak", [("Я", ["я"], P), ("говорю", ["говорить"], V)]),
    ("Вы говорите", WHO_ACTION, "Шумо гап мезанед", "Siz gapirasiz", "You speak", [("Вы", ["вы"], P), ("говорите", ["говорить"], V)]),
    ("Я понимаю", WHO_ACTION, "Ман мефаҳмам", "Men tushunaman", "I understand", [("Я", ["я"], P), ("понимаю", ["понимать"], V)]),
    ("Ты понимаешь", WHO_ACTION, "Ту мефаҳмӣ", "Sen tushunasan", "You understand", [("Ты", ["ты"], P), ("понимаешь", ["понимать"], V)]),
    ("Я понял", WHO_ACTION, "Ман фаҳмидам", "Men tushundim", "I understood", [("Я", ["я"], P), ("понял", ["понять"], V)]),
    ("Ты понял", WHO_ACTION, "Ту фаҳмидӣ", "Sen tushunding", "You understood", [("Ты", ["ты"], P), ("понял", ["понять"], V)]),
    ("Я знаю", WHO_ACTION, "Ман медонам", "Men bilaman", "I know", [("Я", ["я"], P), ("знаю", ["знать"], V)]),
    ("Он знает", WHO_ACTION, "Вай медонад", "U biladi", "He knows", [("Он", ["он"], P), ("знает", ["знать"], V)]),
    ("Я учусь", WHO_ACTION, "Ман таҳсил мекунам", "Men oʻqiyman", "I study", [("Я", ["я"], P), ("учусь", ["учиться"], V)]),
    ("Я живу", WHO_ACTION, "Ман зиндагӣ мекунам", "Men yashayman", "I live", [("Я", ["я"], P), ("живу", ["жить"], V)]),
    ("Они живут", WHO_ACTION, "Онҳо зиндагӣ мекунанд", "Ular yashaydi", "They live", [("Они", ["они"], P), ("живут", ["жить"], V)]),
    ("Я спрошу", WHO_ACTION, "Ман мепурсам", "Men soʻrayman", "I will ask", [("Я", ["я"], P), ("спрошу", ["спросить"], V)]),
    ("Я отвечу", WHO_ACTION, "Ман ҷавоб медиҳам", "Men javob beraman", "I will answer", [("Я", ["я"], P), ("отвечу", ["ответить"], V)]),
    ("Я люблю", WHO_ACTION, "Ман дӯст медорам", "Men sevaman", "I love", [("Я", ["я"], P), ("люблю", ["любить"], V)]),
    ("Я хочу", WHO_ACTION, "Ман мехоҳам", "Men xohlayman", "I want", [("Я", ["я"], P), ("хочу", ["хотеть"], V)]),
    ("Я вижу", WHO_ACTION, "Ман мебинам", "Men koʻraman", "I see", [("Я", ["я"], P), ("вижу", ["видеть"], V)]),
    ("Я слушаю", WHO_ACTION, "Ман гӯш мекунам", "Men tinglayman", "I am listening", [("Я", ["я"], P), ("слушаю", ["слушать"], V)]),
    ("Я жду", WHO_ACTION, "Ман интизорам", "Men kutyapman", "I am waiting", [("Я", ["я"], P), ("жду", ["ждать"], V)]),
    ("Мы играем", WHO_ACTION, "Мо бозӣ мекунем", "Biz oʻynayapmiz", "We are playing", [("Мы", ["мы"], P), ("играем", ["играть"], V)]),
    ("Я помню", WHO_ACTION, "Ман дар ёд дорам", "Men eslayman", "I remember", [("Я", ["я"], P), ("помню", ["помнить"], V)]),
    ("Ребёнок спит", WHO_ACTION, "Кӯдак хоб аст", "Bola uxlayapti", "The child is sleeping", [("Ребёнок", ["ребёнок", "ребенок"], N), ("спит", ["спать"], V)]),
    ("Друг идёт", WHO_ACTION, "Дӯст меояд", "Doʻst kelyapti", "A friend is coming", [("Друг", ["друг"], N), ("идёт", ["идти"], V)]),
    ("Человек работает", WHO_ACTION, "Одам кор мекунад", "Odam ishlayapti", "A person is working", [("Человек", ["человек"], N), ("работает", ["работать"], V)]),
    ("Бабушка спит", WHO_ACTION, "Бибӣ хоб аст", "Buvi uxlayapti", "Grandma is sleeping", [("Бабушка", ["бабушка"], N), ("спит", ["спать"], V)]),
    ("Мама работает", WHO_ACTION, "Модар кор мекунад", "Ona ishlayapti", "Mom is working", [("Мама", ["мама"], N), ("работает", ["работать"], V)]),
    # Кто + действие + что
    ("Я пью воду", WHO_ACTION_WHAT, "Ман об менӯшам", "Men suv ichaman", "I drink water", [("Я", ["я"], P), ("пью", ["пить"], V), ("воду", ["вода"], N)]),
    ("Я пью чай", WHO_ACTION_WHAT, "Ман чой менӯшам", "Men choy ichaman", "I drink tea", [("Я", ["я"], P), ("пью", ["пить"], V), ("чай", ["чай"], N)]),
    ("Я ем хлеб", WHO_ACTION_WHAT, "Ман нон мехӯрам", "Men non yeyman", "I eat bread", [("Я", ["я"], P), ("ем", ["есть"], V), ("хлеб", ["хлеб"], N)]),
    ("Я читаю книгу", WHO_ACTION_WHAT, "Ман китоб мехонам", "Men kitob oʻqiyman", "I am reading a book", [("Я", ["я"], P), ("читаю", ["читать"], V), ("книгу", ["книга"], N)]),
    ("Я пишу письмо", WHO_ACTION_WHAT, "Ман мактуб менависам", "Men xat yozyapman", "I am writing a letter", [("Я", ["я"], P), ("пишу", ["писать"], V), ("письмо", ["письмо"], N)]),
    ("Я знаю ответ", WHO_ACTION_WHAT, "Ман ҷавобро медонам", "Men javobni bilaman", "I know the answer", [("Я", ["я"], P), ("знаю", ["знать"], V), ("ответ", ["ответ"], N)]),
    ("Я вижу дом", WHO_ACTION_WHAT, "Ман хонаро мебинам", "Men uyni koʻryapman", "I see the house", [("Я", ["я"], P), ("вижу", ["видеть"], V), ("дом", ["дом"], N)]),
    ("Я жду друга", WHO_ACTION_WHAT, "Ман дӯстамро интизорам", "Men doʻstimni kutyapman", "I am waiting for a friend", [("Я", ["я"], P), ("жду", ["ждать"], V), ("друга", ["друг"], N)]),
    ("Я вижу человека", WHO_ACTION_WHAT, "Ман одамро мебинам", "Men odamni koʻryapman", "I see a person", [("Я", ["я"], P), ("вижу", ["видеть"], V), ("человека", ["человек"], N)]),
    ("Я люблю бабушку", WHO_ACTION_WHAT, "Ман бибиамро дӯст медорам", "Men buvimni yaxshi koʻraman", "I love my grandma", [("Я", ["я"], P), ("люблю", ["любить"], V), ("бабушку", ["бабушка"], N)]),
    ("Я люблю маму", WHO_ACTION_WHAT, "Ман модарамро дӯст медорам", "Men onamni yaxshi koʻraman", "I love my mom", [("Я", ["я"], P), ("люблю", ["любить"], V), ("маму", ["мама"], N)]),
    ("Я помню друга", WHO_ACTION_WHAT, "Ман дӯстамро дар ёд дорам", "Men doʻstimni eslayman", "I remember my friend", [("Я", ["я"], P), ("помню", ["помнить"], V), ("друга", ["друг"], N)]),
    ("Я задам вопрос", WHO_ACTION_WHAT, "Ман савол медиҳам", "Men savol beraman", "I will ask a question", [("Я", ["я"], P), ("задам", ["задать"], V), ("вопрос", ["вопрос"], N)]),
    ("Ты знаешь ответ", WHO_ACTION_WHAT, "Ту ҷавобро медонӣ", "Sen javobni bilasan", "You know the answer", [("Ты", ["ты"], P), ("знаешь", ["знать"], V), ("ответ", ["ответ"], N)]),
    ("Мы пьём чай", WHO_ACTION_WHAT, "Мо чой менӯшем", "Biz choy ichamiz", "We drink tea", [("Мы", ["мы"], P), ("пьём", ["пить"], V), ("чай", ["чай"], N)]),
    # Кто/что + какой
    ("Он молодой", WHO_WHAT_KIND, "Вай ҷавон аст", "U yosh", "He is young", [("Он", ["он"], P), ("молодой", ["молодой"], A)]),
    ("Ответ правильный", WHO_WHAT_KIND, "Ҷавоб дуруст аст", "Javob toʻgʻri", "The answer is correct", [("Ответ", ["ответ"], N), ("правильный", ["правильный"], A)]),
    ("Дом большой", WHO_WHAT_KIND, "Хона калон аст", "Uy katta", "The house is big", [("Дом", ["дом"], N), ("большой", ["большой"], A)]),
    ("Вода холодная", WHO_WHAT_KIND, "Об хунук аст", "Suv sovuq", "The water is cold", [("Вода", ["вода"], N), ("холодная", ["холодный"], A)]),
    ("Чай горячий", WHO_WHAT_KIND, "Чой гарм аст", "Choy issiq", "The tea is hot", [("Чай", ["чай"], N), ("горячий", ["горячий"], A)]),
    ("Друг близкий", WHO_WHAT_KIND, "Дӯст наздик аст", "Doʻst yaqin", "The friend is close", [("Друг", ["друг"], N), ("близкий", ["близкий"], A)]),
]


def _find_word(db: Session, dictionary_id: int, candidates: list[str]) -> Word | None:
    for text in candidates:
        word = (
            db.query(Word)
            .filter(Word.dictionary_id == dictionary_id, func.lower(func.trim(Word.word)) == text.lower())
            .order_by(Word.id)
            .first()
        )
        if word is not None:
            return word
    return None


def _ensure_templates(db: Session) -> dict[str, MiniPhraseTemplate]:
    out = {}
    for name, texts in TEMPLATES.items():
        t = db.query(MiniPhraseTemplate).filter(MiniPhraseTemplate.name == name).first()
        if t is None:
            t = MiniPhraseTemplate(name=name, distractor_count=2, enabled=True, **texts)
            db.add(t)
            db.flush()
        out[name] = t
    return out


def fill_starter(db: Session, dictionary: Dictionary) -> dict:
    """Adds the starter set to `dictionary` (a Russian one). Returns what was
    created, what already existed and what was skipped for missing words."""
    templates = _ensure_templates(db)
    existing = {
        normalize_answer(t)
        for (t,) in db.query(MiniPhrase.text).filter(MiniPhrase.dictionary_id == dictionary.id).all()
    }
    created: list[str] = []
    already: list[str] = []
    skipped: list[dict] = []
    forms_added: list[str] = []
    for text, template_name, tg, uz, en, parts in STARTER:
        if normalize_answer(text) in existing:
            already.append(text)
            continue
        resolved = []
        missing = []
        for part_text, bases, _role in parts:
            word = _find_word(db, dictionary.id, bases)
            if word is None:
                missing.append(bases[0])
            resolved.append(word)
        if missing:
            skipped.append({"text": text, "missing_words": missing})
            continue

        mp = MiniPhrase(
            dictionary_id=dictionary.id,
            template_id=templates[template_name].id,
            text=text,
            translation_tg=tg,
            translation_uz=uz,
            translation_en=en,
            enabled=True,
        )
        for position, ((part_text, _bases, role), word) in enumerate(zip(parts, resolved), start=1):
            if word.role is None:
                word.role = role
            form_id = None
            if part_text.lower() != word.word.strip().lower():
                form = next(
                    (f for f in word.forms if f.language == dictionary.language and f.text.strip().lower() == part_text.lower()),
                    None,
                )
                if form is None:
                    form = WordForm(word_id=word.id, language=dictionary.language, text=part_text.lower())
                    db.add(form)
                    db.flush()
                    if form not in word.forms:
                        word.forms.append(form)
                    forms_added.append(f"{word.word} → {part_text.lower()}")
                form_id = form.id
            mp.parts.append(MiniPhrasePart(position=position, text=part_text, word_id=word.id, word_form_id=form_id))
        db.add(mp)
        db.flush()
        existing.add(normalize_answer(text))
        created.append(text)
    return {"created": created, "already": already, "skipped": skipped, "forms_added": forms_added}


def fill_phrases(db: Session, dictionary: Dictionary, phrases: list[dict]) -> dict:
    """Adds hand-written phrases ({text, tg, uz, en, parts}) like fill_starter,
    but each phrase's template is derived from its roles (the same rule as
    AI-generated phrases), creating missing templates. The report also lists
    every missing word with how many phrases it would unlock."""
    from app.mini_phrases.generate import _template_name, _template_texts
    from app.mini_phrases.render import DEFAULT_EXPLANATIONS

    templates = {t.name: t for t in db.query(MiniPhraseTemplate).all()}
    existing = {
        normalize_answer(t)
        for (t,) in db.query(MiniPhrase.text).filter(MiniPhrase.dictionary_id == dictionary.id).all()
    }
    created: list[str] = []
    already: list[str] = []
    skipped: list[dict] = []
    forms_added: list[str] = []
    templates_created: list[str] = []
    missing_count: dict[str, int] = {}
    found: dict[tuple, Word | None] = {}
    for item in phrases:
        text, parts = item["text"], item["parts"]
        if normalize_answer(text) in existing:
            already.append(text)
            continue
        resolved = []
        missing = []
        for _part_text, bases, _role in parts:
            key = tuple(bases)
            if key not in found:
                found[key] = _find_word(db, dictionary.id, bases)
            if found[key] is None:
                missing.append(bases[0])
            resolved.append(found[key])
        if missing:
            skipped.append({"text": text, "missing_words": missing})
            for m in set(missing):
                missing_count[m] = missing_count.get(m, 0) + 1
            continue

        roles = [word.role or role for (_t, _b, role), word in zip(parts, resolved)]
        # A named topic template (general explanation, any length) or one per role pattern.
        name = item.get("template") or _template_name(roles)
        texts = (
            {f"explanation_{lang}": DEFAULT_EXPLANATIONS[lang] for lang in ("ru", "tg", "uz")}
            if item.get("template")
            else _template_texts(roles)
        )
        template = templates.get(name)
        if template is None:
            template = MiniPhraseTemplate(name=name, distractor_count=2, enabled=True, **texts)
            db.add(template)
            db.flush()
            templates[name] = template
            templates_created.append(name)
        mp = MiniPhrase(
            dictionary_id=dictionary.id,
            template_id=template.id,
            text=text,
            translation_tg=item["tg"],
            translation_uz=item.get("uz"),
            translation_en=item.get("en"),
            enabled=True,
        )
        for position, ((part_text, _bases, role), word) in enumerate(zip(parts, resolved), start=1):
            if word.role is None:
                word.role = role
            form_id = None
            if part_text.lower() != word.word.strip().lower():
                form = next(
                    (f for f in word.forms if f.language == dictionary.language and f.text.strip().lower() == part_text.lower()),
                    None,
                )
                if form is None:
                    form = WordForm(word_id=word.id, language=dictionary.language, text=part_text.lower())
                    db.add(form)
                    db.flush()
                    if form not in word.forms:
                        word.forms.append(form)
                    forms_added.append(f"{word.word} → {part_text.lower()}")
                form_id = form.id
            mp.parts.append(MiniPhrasePart(position=position, text=part_text, word_id=word.id, word_form_id=form_id))
        db.add(mp)
        db.flush()
        existing.add(normalize_answer(text))
        created.append(text)
    missing_words = sorted(({"word": w, "phrases": n} for w, n in missing_count.items()), key=lambda m: -m["phrases"])
    return {
        "total": len(phrases),
        "created": created,
        "already": already,
        "skipped": skipped,
        "forms_added": forms_added,
        "templates_created": templates_created,
        "missing_words": missing_words,
    }
