from app.models.achievement import Achievement, UserAchievement, UserActivityDay
from app.models.admin import Admin
from app.models.category import Category
from app.models.dictionary import Dictionary
from app.models.exercise import ExerciseSettings
from app.models.import_job import ImportJob
from app.models.learning import LearnedWord, LearningSession, LearningSessionItem
from app.models.learning_settings import LearningSettings
from app.models.lesson import Lesson, LessonExercise, LessonWord
from app.models.phrase import Phrase, PhraseCategory, UserPhraseOpen
from app.models.rating import (
    RatingSettings,
    Rank,
    Season,
    SeasonHistory,
    UserRankPosition,
    UserRating,
    UserReviewPoints,
    UserWordPoints,
)
from app.models.user import User
from app.models.word import Word, WordForm, WordTopic, WordTranslation
from app.models.word_level import WordLevel
from app.models.word_progress import WordProgress
from app.models.word_attempt import WordAttempt
from app.models.priority import PrioritySettings, PriorityLevelBand
from app.models.api_key import ApiKey
from app.models.notification import Notification, PushToken, ReminderRule, ReminderSettings, UserPrepState, UserStudyTime
from app.models.quest import Quest, QuestWord, UserQuestWordDay
from app.models.slogan import Slogan, UserDailySlogan
from app.models.status import StatusEmoji, StatusPhrase
from app.models.premium import PremiumGrant, PremiumSettings
from app.models.promo import PromoActivation, PromoCode, PromoLink
from app.models.text_check import TextCheckCache, TextCheckRun, TextCheckSettings

__all__ = [
    "StatusEmoji",
    "StatusPhrase",
    "Admin",
    "User",
    "Dictionary",
    "Category",
    "Word",
    "WordForm",
    "WordTranslation",
    "Phrase",
    "PhraseCategory",
    "UserPhraseOpen",
    "LearnedWord",
    "LearningSession",
    "LearningSessionItem",
    "ExerciseSettings",
    "ImportJob",
    "Lesson",
    "LessonWord",
    "LessonExercise",
    "WordProgress",
    "WordAttempt",
    "PrioritySettings",
    "PriorityLevelBand",
    "LearningSettings",
    "Achievement",
    "UserAchievement",
    "UserActivityDay",
    "PushToken",
    "ReminderRule",
    "ReminderSettings",
    "UserStudyTime",
    "UserPrepState",
    "ApiKey",
    "RatingSettings",
    "Rank",
    "Season",
    "SeasonHistory",
    "UserRankPosition",
    "UserRating",
    "UserReviewPoints",
    "UserWordPoints",
    "WordLevel",
    "Notification",
    "Quest",
    "QuestWord",
    "Slogan",
    "UserDailySlogan",
    "PremiumGrant",
    "PremiumSettings",
    "PromoActivation",
    "PromoCode",
    "PromoLink",
    "UserQuestWordDay",
    "TextCheckSettings",
    "TextCheckRun",
    "TextCheckCache",
]
from app.models.user_event import UserEvent
from app.models.client_error import ClientError
from app.models.friendship import Friendship
from app.models.mini_phrase import (
    LessonMiniPhrase,
    MiniPhrase,
    MiniPhrasePart,
    MiniPhraseSettings,
    MiniPhraseTemplate,
    UserMiniPhraseDone,
    UserMiniPhrasePoints,
)
# Многоязычная основа: понятие + языковые записи (см. docs/multilingual-migration.md).
# Импорт нужен, чтобы Alembic видел новые таблицы при автогенерации миграций.
from app.models.concept import (
    Concept,
    ConceptTopic,
    PhraseConcept,
    PhraseEntry,
    WordEntry,
    WordEntryForm,
)
# Языки как данные: завести новый язык можно из админки, без правки кода.
from app.models.language import Language
from app.models.achievement import UserStreakFreeze  # noqa: F401
from app.models.team import Team, TeamInvite, TeamMember  # noqa: F401
from app.models.season_pass import PassClaim, PassSettings, PassTemplate, PassXpEvent, SeasonPass, UserCosmetic  # noqa: F401
# «Повторить сегодня»: зафиксированные списки (app/memory/review_lists.py).
from app.models.review_list import ReviewList, ReviewListWord
