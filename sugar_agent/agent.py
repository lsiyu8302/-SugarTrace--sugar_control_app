import json
import re
from datetime import datetime
from openai import OpenAI
from config import DASHSCOPE_API_KEY
from database import (
    fuzzy_search_food_knowledge, upsert_food_knowledge,
    insert_intake_record, delete_intake_record,
    get_daily_total_sugar, get_all_settings,
    get_records_by_date, get_records_by_range,
)
from tavily_search import search_food_sugar_info

_client = OpenAI(
    api_key=DASHSCOPE_API_KEY,
    base_url="https://dashscope.aliyuncs.com/compatible-mode/v1",
    timeout=35,
)

# ── System Prompt: minimal ReAct guide, zero tool mentions ───────────
SYSTEM_PROMPT = """你是"控糖小助手"，帮助用户了解食物含糖量并记录每日糖分摄入。

## 推理指令
结合【完整对话历史】与【最新消息】整体推断用户意图，不要孤立分析最新一条。
常见意图示例（用于辅助推理，非穷举）：
- 询问含糖量：查询食物含糖量/热量
- 记录摄入：用户说"记录"/"吃了"/"喝了"，附有具体食物名
- 跟进记录：对上次查询说"帮我记录"/"记一下"，食物名从历史推断，若历史中已有营养数据可直接使用
- 澄清：食物名太模糊（只有大类如"奶茶"/"蛋糕"），需询问具体品牌/品种
- 纠正：修改刚才记录的食物名/规格/数值
- 撤销：用户说没吃/没喝/只是问问，需删除上一条记录
- 总结建议：查询摄入记录并给出健康建议
- 无关话题：礼貌拒答

## 食物名称与规格提取
- food_name 只含「品牌名+产品名」，如"霸王茶姬 伯牙绝弦"、"CoCo珍珠奶茶"
- serving_size 单独提取：容量(500ml)、杯型(大杯)、重量(100g)等规格
- 去掉修饰词：新品、限定、联名等
- 纠正错别字：根据食物语境判断（如饮品语境中"芯片一抹山月"→"一抹山月"）
- 例："记录星巴克焦糖拿铁大杯" → food_name=星巴克焦糖拿铁，serving_size=大杯

## 数据获取优先级
1. 优先搜索本地知识库（速度最快，应始终第一步）
2. 知识库未命中 → 判断自身训练知识是否有把握给出准确数值（非估算范围）→ 有则直接使用并缓存
3. 自身不确定 → 联网搜索，搜到后缓存到知识库
4. 均无可靠数据 → 告知用户暂无，可给同类估算范围但必须标注「（估算值，仅供参考）」

## 回复格式
- 查询：「[食物名][规格] 含糖量约Xg，热量约X大卡，属于[低/中/高]糖食物🍬。需要帮您记录吗？」
  低糖 <5g/100g；中糖 5-15g；高糖 >15g
- 记录：「✅ 已记录您摄入的[食物名][规格]，含糖Xg，热量X大卡。今日共摄入Xg，剩余Xg。」超标追加⚠️提醒。
- 撤销：「↩️ 已撤销刚才的记录！今日已摄入Xg，剩余Xg。」
- 纠正：「↩️ 已更正！✅ 重新记录[食物名][规格]（含糖Xg）。今日共摄入Xg，剩余Xg。」
- 无关：「抱歉，我只能帮您解答食物含糖量和控糖相关的问题😊」

## 数据准确性（严格执行）
- 含糖量/热量必须来自知识库、搜索结果或有把握的训练知识，严禁编造
- 今日摄入总量与剩余额度：必须来自 record_intake / delete_intake 工具返回的 daily_total 字段，严禁根据系统状态自行计算或从对话历史推算
- 严禁占位符：回复中所有数字必须是真实数值，不得出现"X"、"N"等

## 操作诚信要求（严禁违反）
- 声称"✅ 已记录"：必须已成功调用 record_intake 工具并收到 success:true 的响应，才能写这句话
- 声称"↩️ 已撤销"：必须已成功调用 delete_intake 工具并收到 success:true 的响应，才能写这句话
- 禁止仅凭对话历史推断操作已完成——调用工具是唯一合法的操作方式，绝对不能跳过"""

_NO_THINK = {"enable_thinking": False}
_MAX_HISTORY = 10
_MAX_ROUNDS = 10

# ── Tool definitions (fully self-describing, no overlap with system prompt) ──
TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "search_knowledge_base",
            "description": (
                "在本地食物营养知识库中搜索含糖量、热量等数据。"
                "任何涉及食物营养的操作都必须首先调用此工具，支持模糊匹配。"
                "返回 null 表示知识库中无记录，此时再考虑使用模型知识或联网搜索。"
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "food_name": {
                        "type": "string",
                        "description": "食物名称（品牌+产品名，不含规格），如'霸王茶姬 伯牙绝弦'"
                    }
                },
                "required": ["food_name"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "upsert_knowledge_base",
            "description": (
                "将食物营养数据写入/更新本地知识库，供未来快速查询。"
                "当数据来自模型训练知识或联网搜索（非估算）时必须调用此工具缓存，"
                "避免重复查询。估算数据不得写入。"
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "name": {"type": "string", "description": "食物名称（品牌+产品名，不含规格）"},
                    "sugar_g": {"type": "number", "description": "含糖量（克）"},
                    "calories": {"type": ["number", "null"], "description": "热量（大卡），不确定填null"},
                    "category": {
                        "type": "string",
                        "enum": ["奶茶", "甜品", "糖果", "烘焙", "水果", "其他"],
                        "description": "食物分类"
                    },
                    "serving_size": {
                        "type": ["string", "null"],
                        "description": "标准规格，如'500ml'、'标准杯'、'100g'"
                    },
                    "source": {
                        "type": "string",
                        "enum": ["model_knowledge", "tavily", "nutrition_label"],
                        "description": (
                            "数据来源，必须如实填写："
                            "model_knowledge — 数据来自模型预训练知识，本轮未调用 web_search；"
                            "tavily — 本轮调用了 web_search 工具并从搜索结果中提取；"
                            "nutrition_label — 来自用户提供的食品营养成分表图片"
                        )
                    }
                },
                "required": ["name", "sugar_g", "category", "source"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "record_intake",
            "description": (
                "将用户的食物摄入记录写入数据库。"
                "仅在用户明确表示要记录（说了'记录'/'吃了'/'喝了'等意图）且已有可靠营养数据时调用。"
                "用估算数据记录时须将 is_estimated 设为 true 并获得用户确认。"
                "调用后返回最新今日总摄入量。"
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "food_name": {"type": "string", "description": "食物名称（品牌+产品名）"},
                    "sugar_g": {"type": "number", "description": "含糖量（克）"},
                    "calories": {"type": ["number", "null"], "description": "热量（大卡）"},
                    "category": {
                        "type": "string",
                        "enum": ["奶茶", "甜品", "糖果", "烘焙", "水果", "其他"]
                    },
                    "serving_size": {
                        "type": ["string", "null"],
                        "description": "本次实际规格，如'大杯'、'500ml'"
                    },
                    "is_estimated": {
                        "type": "boolean",
                        "description": "营养数据是否为估算值，默认 false"
                    }
                },
                "required": ["food_name", "sugar_g", "category", "is_estimated"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "delete_intake",
            "description": (
                "删除一条摄入记录。用于以下两种场景：\n"
                "1. 用户撤销：说了'没喝'/'没吃'/'只是问问'/'取消'/'撤销'等，删除上一条记录\n"
                "2. 纠正前清理：用户纠正错误记录时，先删除原记录再重新记录正确内容\n"
                "record_id 优先使用系统提示中注入的上一条记录ID。"
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "record_id": {
                        "type": "integer",
                        "description": "要删除的记录ID（来自系统提示中的上一条记录ID）"
                    }
                },
                "required": ["record_id"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "query_records",
            "description": (
                "查询指定日期或日期区间的摄入记录，用于生成健康总结或控糖建议。"
                "用户说'今天吃了什么'/'本周情况'/'给我建议'等时调用。"
                "不传参数默认查今日。"
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "date": {
                        "type": ["string", "null"],
                        "description": "查单日，格式 YYYY-MM-DD"
                    },
                    "start_date": {
                        "type": ["string", "null"],
                        "description": "区间开始日期，格式 YYYY-MM-DD"
                    },
                    "end_date": {
                        "type": ["string", "null"],
                        "description": "区间结束日期，格式 YYYY-MM-DD"
                    }
                }
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "web_search",
            "description": (
                "联网搜索食物的含糖量/热量等营养信息。"
                "仅在知识库未命中且自身训练知识不确定时调用，避免不必要的网络请求。"
                "搜索成功获得可靠数据后，必须随即调用 upsert_knowledge_base 缓存结果。"
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "food_name": {
                        "type": "string",
                        "description": "食物名称，用于搜索含糖量和热量"
                    }
                },
                "required": ["food_name"]
            }
        }
    },
]


# ── Helpers ───────────────────────────────────────────────────────────

def _strip_think(text: str) -> str:
    return re.sub(r"<think>.*?</think>", "", text, flags=re.DOTALL).strip()


def _extract_json(text: str) -> str:
    text = _strip_think(text)
    m = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, re.DOTALL)
    if m:
        return m.group(1)
    m = re.search(r"\{.*\}", text, re.DOTALL)
    if m:
        return m.group(0)
    return text


# ── Tool executor ─────────────────────────────────────────────────────

def _execute_tool(name: str, args: dict, today: str,
                  last_record_id: int | None) -> tuple[str, dict]:
    """Execute a tool call and return (result_text, meta).
    meta keys: record_id (int), deleted (bool), is_estimated (bool)
    """
    meta: dict = {}

    if name == "search_knowledge_base":
        food_name = args.get("food_name", "")
        # Multi-strategy: full fuzzy name first, then space-separated components
        result = fuzzy_search_food_knowledge(food_name)
        if not result:
            parts = [p for p in food_name.split() if len(p) >= 2]
            for part in parts:
                result = fuzzy_search_food_knowledge(part)
                if result:
                    break
        return (json.dumps(result, ensure_ascii=False) if result else "null"), meta

    elif name == "upsert_knowledge_base":
        try:
            upsert_food_knowledge(
                name=args["name"],
                sugar_g=args["sugar_g"],
                calories=args.get("calories"),
                category=args.get("category", "其他"),
                serving_size=args.get("serving_size"),
                source=args.get("source", "model_knowledge"),
            )
            return "已成功写入知识库", meta
        except Exception as e:
            return f"写入失败：{e}", meta

    elif name == "record_intake":
        try:
            record_id = insert_intake_record(
                food_name=args["food_name"],
                sugar_g=args["sugar_g"],
                calories=args.get("calories"),
                category=args.get("category", "其他"),
                serving_size=args.get("serving_size"),
            )
            meta["record_id"] = record_id
            meta["is_estimated"] = bool(args.get("is_estimated", False))
            total = get_daily_total_sugar(today)
            return json.dumps(
                {"success": True, "record_id": record_id, "daily_total": round(total, 1)},
                ensure_ascii=False
            ), meta
        except Exception as e:
            return json.dumps({"success": False, "error": str(e)}, ensure_ascii=False), meta

    elif name == "delete_intake":
        rid = args.get("record_id") or last_record_id
        if not rid:
            return "无可删除记录：未提供 record_id 且会话内无上一条记录", meta
        try:
            ok = delete_intake_record(int(rid))
            meta["deleted"] = ok
            total = get_daily_total_sugar(today)
            return json.dumps(
                {"success": ok, "daily_total": round(total, 1)},
                ensure_ascii=False
            ), meta
        except Exception as e:
            return json.dumps({"success": False, "error": str(e)}, ensure_ascii=False), meta

    elif name == "query_records":
        date = args.get("date")
        start = args.get("start_date")
        end = args.get("end_date")
        if date:
            rows = get_records_by_date(date)
        elif start and end:
            rows = get_records_by_range(start, end)
        else:
            rows = get_records_by_date(today)
        return json.dumps(rows, ensure_ascii=False), meta

    elif name == "web_search":
        text = search_food_sugar_info(args.get("food_name", ""))
        return text, meta

    return f"未知工具：{name}", meta


# ── Main entry point ──────────────────────────────────────────────────

def chat(message: str,
         image_base64: str | None = None,
         history: list[dict] | None = None,
         last_record_id: int | None = None) -> dict:
    """
    ReAct agent entry point.

    Returns:
      reply        str          — final assistant text
      food_info    dict|None    — {name, sugar_g, calories, category, serving_size}
      recorded     True|None    — True if a record was inserted
      record_id    int|None     — ID of the inserted record
      deleted      bool         — True if a record was deleted
      is_estimated bool         — True if recorded data was estimated
      (+ over-limit fields when recorded: daily_total, limit, is_over_limit,
         over_amount, warning_level)
    """
    settings = get_all_settings()
    daily_limit = float(settings.get("daily_sugar_limit", 50))
    _now = datetime.now()
    today = _now.strftime("%Y-%m-%d")
    _weekday_cn = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"][_now.weekday()]
    history = (history or [])[-_MAX_HISTORY:]

    # ── Image: vision identification → augment message ────────────────
    if image_base64:
        _VL_PROMPT = (
            "从图片中识别食物信息，只输出JSON，不要有任何多余文字：\n"
            '{"food_name":"食物名称","serving_size":"规格或null",'
            '"from_label":false,"sugar_g":null,"calories":null,"unrecognized":false}\n'
            "字段规则：\n"
            "- food_name：只写「品牌名+产品名」，严禁包含容量/杯型/括号规格说明\n"
            "- serving_size：所有规格写这里，如'500ml'、'标准杯'、'100g'，没有则null\n"
            "- 不能只写'奶茶'/'果汁'等大类，food_name 必须尽量具体\n"
            "- 营养成分表/配料表：from_label=true，填入 sugar_g 和 calories\n"
            "- 图片不清晰或与食物无关：unrecognized=true，其余字段null\n"
            "- 食物/饮品实物：from_label=false，sugar_g/calories留null"
        )
        vl_resp = _client.chat.completions.create(
            model="qwen3-vl-flash-2026-01-22",
            extra_body=_NO_THINK,
            messages=[
                {"role": "system", "content": _VL_PROMPT},
                {"role": "user", "content": [
                    {"type": "image_url",
                     "image_url": {"url": f"data:image/jpeg;base64,{image_base64}"}},
                    {"type": "text",
                     "text": message or "请识别这个食物/饮品/标签的名称和营养信息"},
                ]},
            ],
        )
        try:
            vl_id = json.loads(
                _extract_json(_strip_think(vl_resp.choices[0].message.content))
            )
        except Exception:
            vl_id = {}

        img_food_name = vl_id.get("food_name") or None
        img_serving   = vl_id.get("serving_size") or None

        if vl_id.get("unrecognized") or not img_food_name:
            return {
                "reply": "图片不太清晰或无法识别食物，请重新拍摄清晰的食物照片或营养标签📷",
                "food_info": None, "recorded": None,
                "deleted": False, "is_estimated": False, "record_id": None,
            }

        sv_str = f"（{img_serving}）" if img_serving else ""
        if vl_id.get("from_label") and vl_id.get("sugar_g") is not None:
            label_sugar = float(vl_id["sugar_g"])
            label_cal   = float(vl_id["calories"]) if vl_id.get("calories") is not None else None
            try:
                upsert_food_knowledge(
                    name=img_food_name, sugar_g=label_sugar, calories=label_cal,
                    category="其他", serving_size=img_serving, source="nutrition_label",
                )
            except Exception:
                pass
            cal_str = f"、热量{label_cal:.0f}kcal" if label_cal is not None else ""
            img_augment = (
                f"【图片识别：营养标签】食物名称：{img_food_name}{sv_str}，"
                f"含糖量{label_sugar}g{cal_str}"
            )
        else:
            img_augment = f"【图片识别：食物实物】食物名称：{img_food_name}{sv_str}"

        message = f"{message}\n{img_augment}" if message else img_augment

    # ── Build system prompt with real-time daily status ───────────────
    total_now = get_daily_total_sugar(today)
    rem_now = daily_limit - total_now
    status_str = (
        f"今日糖分已超标{abs(rem_now):.1f}g（限额{daily_limit:.0f}g，已摄入{total_now:.1f}g）"
        if rem_now < 0 else
        f"今日已摄入{total_now:.1f}g，剩余额度{rem_now:.1f}g（限额{daily_limit:.0f}g）"
    )
    system = (
        SYSTEM_PROMPT
        + f"\n\n【当前日期：{today} {_weekday_cn}】"
        + f"\n【今日摄入状态（实时）：{status_str}】"
    )
    if last_record_id:
        system += f"\n【上一条记录ID = {last_record_id}，撤销或纠正时使用此ID】"

    # ── ReAct loop ────────────────────────────────────────────────────
    messages = [
        {"role": "system", "content": system},
        *[{"role": h["role"], "content": h["content"]} for h in history],
        {"role": "user", "content": message},
    ]

    result_meta: dict = {}
    food_info: dict | None = None
    reply = "抱歉，处理您的请求时出现了问题，请稍后重试。"

    for _ in range(_MAX_ROUNDS):
        resp = _client.chat.completions.create(
            model="qwen3-max-2026-01-23",
            extra_body=_NO_THINK,
            tools=TOOLS,
            tool_choice="auto",
            messages=messages,
        )
        choice = resp.choices[0]
        msg = choice.message
        messages.append(msg)

        if choice.finish_reason != "tool_calls" or not msg.tool_calls:
            reply = _strip_think(msg.content or "")
            break

        for tc in msg.tool_calls:
            try:
                args = json.loads(tc.function.arguments)
            except json.JSONDecodeError:
                args = {}

            tool_result, meta = _execute_tool(
                tc.function.name, args, today, last_record_id
            )

            # Accumulate non-falsy metadata
            for k, v in meta.items():
                if v is not None and v is not False:
                    result_meta[k] = v

            # ── Capture food_info from tool results ───────────────
            # Path A: direct KB hit
            if tc.function.name == "search_knowledge_base" and tool_result != "null":
                try:
                    food_info = json.loads(tool_result)
                except Exception:
                    pass

            # Path B: model knowledge or web_search → upsert carries full nutrition args
            # Ensures food_info is never None after a successful data fetch + cache
            elif tc.function.name == "upsert_knowledge_base" and food_info is None:
                candidate = {
                    "name": args.get("name"),
                    "sugar_g": args.get("sugar_g"),
                    "calories": args.get("calories"),
                    "category": args.get("category", "其他"),
                    "serving_size": args.get("serving_size"),
                }
                if candidate["name"] and isinstance(candidate["sugar_g"], (int, float)):
                    food_info = candidate

            messages.append({
                "role": "tool",
                "tool_call_id": tc.id,
                "content": tool_result,
            })

    # ── Post-loop: build response ─────────────────────────────────────
    recorded = "record_id" in result_meta
    deleted = result_meta.get("deleted", False)
    is_estimated = result_meta.get("is_estimated", False)
    new_record_id = result_meta.get("record_id")

    # Fresh DB read after all operations for accurate over-limit calculation
    total_after = get_daily_total_sugar(today)

    over_limit: dict = {}
    if recorded and new_record_id:
        over_amount = max(0.0, total_after - daily_limit)
        is_over = over_amount > 0
        if over_amount >= 50:
            wl = "重度"
        elif over_amount >= 30:
            wl = "中度"
        elif over_amount >= 15:
            wl = "轻度"
        else:
            wl = None
        over_limit = {
            "daily_total": round(total_after, 1),
            "limit": daily_limit,
            "is_over_limit": is_over,
            "over_amount": round(over_amount, 1),
            "warning_level": wl,
        }

    return {
        "reply": reply,
        "food_info": food_info,
        "recorded": True if recorded else None,
        "record_id": new_record_id,
        "deleted": deleted,
        "is_estimated": is_estimated,
        **over_limit,
    }


# ── Shopping intent verification ──────────────────────────────────────

_VERIFY_PROMPT = """你是购物意图判断助手。分析手机屏幕内容，判断用户是否正在购物/外卖/点单页面上浏览或准备购买高糖食品。

判定为"是"需同时满足：
1. 确实是购物/外卖/点单场景（有价格、下单按钮等商业元素）
2. 查看的确实是可食用的高糖食品（非同名非食品商品，如"巧克力色"口红、"草莓手机壳"等）
3. 不是在浏览无糖/低糖/代糖的健康替代版本

预过滤检测到的疑似高糖关键词：{food_keywords}

只返回JSON：{{"is_buying_sugar": true/false, "food_name": "具体食品名或null", "confidence": 0.0-1.0}}"""


def verify_shopping_intent(
    screenshot_base64: str | None,
    screen_text: str | None,
    food_keywords: list[str],
) -> dict:
    """Returns {"confirmed": bool, "food_name": str|None}"""
    prompt = _VERIFY_PROMPT.format(
        food_keywords="、".join(food_keywords) if food_keywords else "未知"
    )
    try:
        if screenshot_base64:
            messages = [
                {"role": "system", "content": prompt},
                {"role": "user", "content": [
                    {"type": "image_url",
                     "image_url": {"url": f"data:image/jpeg;base64,{screenshot_base64}"}},
                    {"type": "text", "text": "请根据截图判断用户是否正在购买高糖食品。"},
                ]},
            ]
            resp = _client.chat.completions.create(
                model="qwen3-vl-flash-2026-01-22",
                messages=messages, extra_body=_NO_THINK, timeout=10,
            )
        else:
            messages = [
                {"role": "system", "content": prompt},
                {"role": "user", "content": f"屏幕文字内容：\n{(screen_text or '')[:1000]}"},
            ]
            resp = _client.chat.completions.create(
                model="qwen3-max-2026-01-23",
                messages=messages, extra_body=_NO_THINK, timeout=10,
            )

        data = json.loads(_extract_json(_strip_think(resp.choices[0].message.content)))
        if data.get("is_buying_sugar") and float(data.get("confidence", 0)) >= 0.7:
            return {"confirmed": True, "food_name": data.get("food_name") or None}
        return {"confirmed": False}
    except Exception:
        return {"confirmed": False}
