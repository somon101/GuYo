"""Learning topics: the sign-up question "why are you learning", reused as
the topics words are tagged with and lessons prefer. Fixed in code, like
the sign-up options themselves (mobile/lib/screens/register_screen.dart).
"personal" and "other" carry no words of their own: they mean "no
particular topic", so such a user just gets the most important words."""

from typing import Literal

WordTopicCode = Literal["study", "work", "communication", "travel", "relocation"]
