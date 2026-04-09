from fastapi import FastAPI, HTTPException, Query
from contextlib import asynccontextmanager
from datetime import date as date_type
import asyncio

import database as db
import agent
from models import (
    ChatRequest, ChatResponse,
    IntakeRecordCreate, IntakeRecord,
    DailySummary, SettingsUpdate,
    ShoppingVerifyRequest, ShoppingVerifyResponse,
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    db.init_db()
    yield


app = FastAPI(title="Sugar Control Assistant", version="0.1.0", lifespan=lifespan)


# ── /chat ────────────────────────────────────────────────────────────

@app.post("/chat", response_model=ChatResponse)
async def chat(req: ChatRequest):
    # run sync agent in thread pool so we don't block the event loop
    try:
        history = [{"role": m.role, "content": m.content} for m in req.history]
        result = await asyncio.to_thread(
            agent.chat,
            message=req.message,
            image_base64=req.image_base64,
            history=history,
            last_record_id=req.last_record_id,
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    return ChatResponse(**result)


# ── /record ──────────────────────────────────────────────────────────

@app.post("/record", response_model=dict)
async def add_record(req: IntakeRecordCreate):
    record_id = db.insert_intake_record(
        food_name=req.food_name,
        sugar_g=req.sugar_g,
        calories=req.calories,
        category=req.category.value,
        serving_size=req.serving_size,
    )
    today = date_type.today().isoformat()
    settings = db.get_all_settings()
    daily_limit = float(settings.get("daily_sugar_limit", 50))
    daily_total = db.get_daily_total_sugar(today)
    over_amount = max(0.0, daily_total - daily_limit)
    is_over = over_amount > 0

    if over_amount >= 50:
        warning_level = "重度"
    elif over_amount >= 30:
        warning_level = "中度"
    elif over_amount >= 15:
        warning_level = "轻度"
    else:
        warning_level = None

    return {
        "id": record_id,
        "message": "记录成功",
        "daily_total": round(daily_total, 1),
        "limit": daily_limit,
        "is_over_limit": is_over,
        "over_amount": round(over_amount, 1),
        "warning_level": warning_level,
    }


# ── DELETE /record/{id} ──────────────────────────────────────────────

@app.delete("/record/{record_id}", response_model=dict)
async def delete_record(record_id: int):
    deleted = db.delete_intake_record(record_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="记录不存在")
    return {"message": "已删除"}


# ── DELETE /records/today ─────────────────────────────────────────────

@app.delete("/records/today", response_model=dict)
async def delete_today_records():
    today = date_type.today().isoformat()
    count = db.delete_records_by_date(today)
    return {"message": f"已删除{count}条记录", "count": count}


# ── /records/range  (must be defined BEFORE /records/{date}) ─────────

@app.get("/records/range", response_model=list[IntakeRecord])
async def get_records_range(
    start: str = Query(..., description="YYYY-MM-DD"),
    end: str   = Query(..., description="YYYY-MM-DD"),
):
    rows = db.get_records_by_range(start, end)
    return rows


# ── /records/{date} ──────────────────────────────────────────────────

@app.get("/records/{date}", response_model=list[IntakeRecord])
async def get_records(date: str):
    rows = db.get_records_by_date(date)
    return rows


# ── /daily-summary/{date} ────────────────────────────────────────────

@app.get("/daily-summary/{date}", response_model=DailySummary)
async def daily_summary(date: str):
    records = db.get_records_by_date(date)
    settings = db.get_all_settings()
    daily_limit = float(settings.get("daily_sugar_limit", 50))

    total_sugar = sum(r["sugar_g"] for r in records)
    total_calories = sum(r["calories"] or 0 for r in records)

    return DailySummary(
        date=date,
        total_sugar_g=total_sugar,
        total_calories=total_calories,
        record_count=len(records),
        daily_limit_g=daily_limit,
        remaining_g=max(0.0, daily_limit - total_sugar),
        records=records,
    )


# ── /settings ────────────────────────────────────────────────────────

@app.get("/settings", response_model=dict)
async def get_settings():
    return db.get_all_settings()


@app.put("/settings", response_model=dict)
async def update_settings(req: SettingsUpdate):
    db.upsert_setting(req.key, req.value)
    return {"message": "设置已更新", "key": req.key, "value": req.value}


# ── /verify-shopping-intent ──────────────────────────────────────────

@app.post("/verify-shopping-intent", response_model=ShoppingVerifyResponse)
async def verify_shopping_intent(req: ShoppingVerifyRequest):
    try:
        result = await asyncio.to_thread(
            agent.verify_shopping_intent,
            screenshot_base64=req.screenshot_base64,
            screen_text=req.screen_text,
            food_keywords=req.food_keywords,
        )
    except Exception:
        return ShoppingVerifyResponse(confirmed=False)
    return ShoppingVerifyResponse(**result)


# ── dev entrypoint ───────────────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
