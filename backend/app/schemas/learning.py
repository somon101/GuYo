from pydantic import BaseModel, ConfigDict, Field

from app.schemas.word import WordOut


class CreateLearningSessionIn(BaseModel):
    dictionary_id: int
    count: int = Field(ge=3, le=20)


class LearningSessionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    dictionary_id: int
    total_count: int
    remaining_count: int
    learned_count: int
    is_completed: bool
    # The one word_id currently being shown to the user, or None only when
    # the session is fully completed. Reuses WordOut as-is -- same card the
    # dictionary/editor already use, no separate "learning card" shape.
    current_word: WordOut | None = None


class LearnedCategoryOut(BaseModel):
    category_id: int | None
    category_name: str
    learned_count: int
    # The category's own uploaded picture (see Category.icon_key) --
    # null both for "Без категории" and for a real category whose icon
    # an admin hasn't set yet; the client draws its generic folder icon
    # in either case.
    icon_url: str | None = None
