from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class Event:
    type: str
    message: str
    data: dict[str, Any]


def event(type_: str, message: str, **data: Any) -> Event:
    return Event(type=type_, message=message, data=data)
