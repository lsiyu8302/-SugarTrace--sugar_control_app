from pydantic import BaseModel
from typing import Optional
from enum import Enum


class FoodCategory(str, Enum):
    milk_tea = "奶茶"
    dessert = "甜品"
    candy = "糖果"
    bakery = "烘焙"
    fruit = "水果"
    other = "其他"


# ── Request bodies ──────────────────────────────────────────────────

class HistoryMessage(BaseModel):
    role: str   # "user" | "assistant"
    content: str


class ChatRequest(BaseModel):
    message: str
    image_base64: Optional[str] = None
    history: list[HistoryMessage] = []   # last N turns for context
    last_record_id: Optional[int] = None  # for correction: delete this record before re-recording


class IntakeRecordCreate(BaseModel):
    food_name: str
    serving_size: Optional[str] = None   # e.g. "大杯", "20g", "1块"
    sugar_g: float
    calories: Optional[float] = None
    category: FoodCategory = FoodCategory.other


class SettingsUpdate(BaseModel):
    key: str
    value: str


# ── Response bodies ─────────────────────────────────────────────────

class ChatResponse(BaseModel):
    reply: str
    food_info: Optional[dict] = None
    recorded: Optional[bool] = None
    record_id: Optional[int] = None
    deleted: bool = False
    is_estimated: bool = False
    # Over-limit fields — only present when agent auto-recorded
    daily_total: Optional[float] = None
    limit: Optional[float] = None
    is_over_limit: Optional[bool] = None
    over_amount: Optional[float] = None
    warning_level: Optional[str] = None


class IntakeRecord(BaseModel):
    id: int
    food_name: str
    serving_size: Optional[str]
    sugar_g: float
    calories: Optional[float]
    category: str
    record_time: str
    date_key: str


class DailySummary(BaseModel):
    date: str
    total_sugar_g: float
    total_calories: float
    record_count: int
    daily_limit_g: float
    remaining_g: float
    records: list[IntakeRecord]


class ShoppingVerifyRequest(BaseModel):
    screenshot_base64: Optional[str] = None
    screen_text: Optional[str] = None
    food_keywords: list[str] = []


class ShoppingVerifyResponse(BaseModel):
    confirmed: bool
    food_name: Optional[str] = None


class FoodKnowledge(BaseModel):
    id: int
    name: str
    serving_size: Optional[str]
    sugar_g: float
    calories: Optional[float]
    category: str
    source: Optional[str]
    created_at: str
