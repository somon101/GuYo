"""add word importance and topics, and the user's own topics

  words.importance       1-5, 5 = a beginner needs it first (default 3)
  word_topics            which learning topics a word is useful for
  users.learning_topics  the topics a user picked; NULL = never asked

Seeds a starting importance and topic set for the Russian dictionary's
233 words (matched by word text, so a database without them is simply
untouched). The owner reviews and adjusts them in Admin Web.

Topic letters below: s=study, w=work, c=communication, t=travel,
r=relocation.

Revision ID: c9e3f7a1b5d8
Revises: b8d2e6f0a4c7
Create Date: 2026-09-29 16:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c9e3f7a1b5d8'
down_revision: Union[str, None] = 'b8d2e6f0a4c7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


TOPIC_LETTERS = {"s": "study", "w": "work", "c": "communication", "t": "travel", "r": "relocation"}

# word | importance | topics
SEED = """
Человек|5|c
Друг|4|c
Ребёнок|3|c
Молодой|3|c
Знакомый|3|c
Дом|5|rt
Дверь|3|r
Кот|2|c
Страна|4|tr
Мир|3|t
Российский|2|r
Русский|4|sr
Университет|3|s
Язык|4|src
Город|4|tr
Место|4|trw
В|5|
Перед|3|
У|5|
На|5|
До|4|
После|4|
С|5|
Для|4|
Рядом|4|tr
Над|2|
О|4|
Среди|2|
Из|5|
Сторона|2|t
От|4|
Возле|2|t
Здесь|5|tr
За|3|
Время|5|w
Год|4|
День|5|
Момент|2|
Недавно|2|
Час|4|wt
Долго|3|
Вечер|4|ct
Долгий|2|
Сейчас|5|w
Конец|3|
Вовремя|3|w
Пока|3|c
Глаз|3|
Голова|3|r
Лицо|3|
Рука|3|w
Улыбка|2|c
Работа|5|wr
Дело|3|w
Документ|4|wr
План|3|ws
Идти|5|t
Взять|4|w
Прийти|4|wt
Приехать|4|tr
Видеть|4|
Смотреть|4|
Чувствовать|3|c
Видный|1|
Говорить|5|c
Сказать|5|c
Спросить|4|cst
А|5|
И|5|
Новость|3|c
Задать|3|s
Обсуждать|2|ws
Правда|3|c
Вопрос|4|swc
Ответить|4|sc
Ответ|4|s
Слово|4|s
Знак|2|t
Разговор|3|c
Фильм|2|c
Встреча|3|wc
Отвечать|3|s
Книга|3|s
Думать|4|c
Знать|5|
Понять|5|sc
Решить|3|w
Мнение|2|cs
Значить|2|s
Означать|1|s
Проблема|3|wr
Смысл|2|s
Выбор|2|
Мочь|5|
Хотеть|5|c
Уметь|4|w
Возможность|3|w
Должен|4|w
Быть|5|
Дать|5|
Жить|5|r
Иметь|4|
Оказаться|2|
Получить|4|wr
Работать|5|wr
Сделать|5|w
Сидеть|3|
Стать|3|
Помогать|4|wc
Начать|4|ws
Начаться|3|
Появиться|2|
Менять|2|
Находиться|3|tr
Поднять|2|w
Закончить|4|ws
Произойти|2|
Прошло|2|
Выйти|3|t
Обещать|2|c
Читать|4|s
Развиваться|2|s
Проходить|2|
Измениться|2|
Заболеть|3|r
Открыться|2|t
Понравиться|3|c
Жизнь|3|cr
Отдохнуть|3|t
Меняться|1|
Победа|1|
Оставаться|3|tr
Больше|4|
Меньше|4|
Очень|5|
Почти|3|
Совсем|3|
Столько|2|
Много|5|
Слишком|3|
Намного|2|
Даже|3|
Только|4|
Один|5|
Совершенно|1|
Вдруг|2|
Вместе|4|c
Ещё|5|
Снова|3|
Сразу|3|w
Уже|5|
Раз|3|
Особенно|2|
Всегда|4|
Редко|2|
Часто|3|
Иногда|3|
Вообще|2|
Следующий|3|ts
Случай|2|
Неожиданно|1|
Впервые|2|
Большой|5|
Маленький|4|
Высокий|3|
Далёкий|2|t
Недалеко|3|tr
Далеко|3|tr
Издалека|1|
Белый|3|
Чёрный|3|
Вид|2|
Главный|3|w
Государственный|2|rw
Настоящий|2|
Новый|4|
Нужный|4|wr
Общий|2|
Основной|2|
Полный|2|
Последний|3|
Разный|2|
Собственный|1|
Старый|3|
Хороший|5|c
Хорошо|5|c
Такой|4|
Трудный|3|sw
Случайный|1|
Действительно|2|
Красиво|3|tc
Быстро|4|w
Важно|3|w
Популярный|2|
Трудно|3|sw
Необходимый|2|r
Занятый|3|w
Важный|3|w
Самостоятельно|2|sw
Правильно|4|s
Так|4|
Сильный|2|
Сила|1|
Интересный|3|cst
Сложный|2|s
Простой|3|
Просто|3|
Открытый|2|t
Все|5|
Всё|5|
Он|5|
Она|5|
Они|5|
Мы|5|
Наш|4|
Сам|3|
Свой|3|
Себя|3|
Ты|5|
Это|5|
Этот|5|
Каждый|4|
Другой|4|
Я|5|
Сама|2|
Никто|3|
Где|5|tr
Который|4|
Что|5|
Не|5|
Почему|4|c
Когда|5|
Как|5|
"""


def upgrade() -> None:
    op.add_column('words', sa.Column('importance', sa.Integer(), server_default='3', nullable=False))
    op.create_check_constraint('ck_word_importance_range', 'words', 'importance BETWEEN 1 AND 5')
    op.create_table(
        'word_topics',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('word_id', sa.Integer(), nullable=False),
        sa.Column('topic', sa.String(length=32), nullable=False),
        sa.ForeignKeyConstraint(['word_id'], ['words.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('word_id', 'topic', name='uq_word_topic'),
    )
    op.create_index('ix_word_topics_word_id', 'word_topics', ['word_id'])
    op.add_column('users', sa.Column('learning_topics', sa.JSON(), nullable=True))

    conn = op.get_bind()
    ru_words = sa.text(
        "SELECT w.id FROM words w JOIN dictionaries d ON d.id = w.dictionary_id "
        "WHERE d.language = 'ru' AND w.word = :word"
    )
    for line in SEED.strip().splitlines():
        word, importance, letters = line.split("|")
        for (word_id,) in conn.execute(ru_words, {"word": word}).fetchall():
            conn.execute(sa.text("UPDATE words SET importance = :i WHERE id = :id"), {"i": int(importance), "id": word_id})
            for letter in letters:
                conn.execute(
                    sa.text("INSERT INTO word_topics (word_id, topic) VALUES (:id, :t) ON CONFLICT DO NOTHING"),
                    {"id": word_id, "t": TOPIC_LETTERS[letter]},
                )


def downgrade() -> None:
    op.drop_column('users', 'learning_topics')
    op.drop_index('ix_word_topics_word_id', table_name='word_topics')
    op.drop_table('word_topics')
    op.drop_constraint('ck_word_importance_range', 'words', type_='check')
    op.drop_column('words', 'importance')
