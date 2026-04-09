# 糖迹 · Sugar Control Assistant

一款面向控糖人群的 Android AI 助手应用。通过与 AI 对话记录每日含糖食品摄入、查询食物糖分、统计摄入趋势，并在购物时实时检测高糖食品并弹出提醒。

---

## 功能概览

| 功能 | 说明 |
|------|------|
| **AI 问答** | 用自然语言查询任意食物的含糖量、热量，支持拍照识别 |
| **摄入记录** | 对话中说"帮我记录"即自动写入数据库，无需手动填表 |
| **撤销记录** | 说"撤销刚才的记录"即可删除最近一条 |
| **每日统计** | 可视化展示当日/历史糖分摄入趋势，与自设上限对比 |
| **购物预警** | 通过无障碍服务监控其他购物 App，检测到高糖食品时弹出悬浮提醒 |
| **本地知识库** | AI 查询结果自动缓存到本地 SQLite，下次查询秒回无需联网 |

---

## 整体架构

```
┌─────────────────────────────┐
│   Flutter 前端 (Android)    │
│  chat / stats / settings    │
│  + 无障碍服务购物监控        │
└────────────┬────────────────┘
             │ HTTP (局域网 / 公网)
┌────────────▼────────────────┐
│   FastAPI 后端 (Python)     │
│                             │
│  ┌──────────────────────┐   │
│  │   ReAct Agent        │   │
│  │  (Qwen3 via          │   │
│  │   Dashscope API)     │   │
│  └──────┬───────────────┘   │
│         │ 工具调用           │
│  ┌──────▼───────────────┐   │
│  │  SQLite 知识库 +      │   │
│  │  摄入记录数据库       │   │
│  └──────────────────────┘   │
│         │ 知识库未命中时     │
│  ┌──────▼───────────────┐   │
│  │   Tavily 联网搜索    │   │
│  └──────────────────────┘   │
└─────────────────────────────┘
```

**Agent 工作流（ReAct 架构）：**
1. 用户发送消息 → Agent 分析意图
2. 优先搜索本地知识库
3. 知识库未命中 → 尝试用模型自身知识回答
4. 模型也不确定 → 调用 Tavily 联网搜索
5. 获取数据后自动写入知识库缓存
6. 用户有记录意图时调用 `record_intake` 工具写入数据库

---

## 目录结构

```
sugar_control_assistant/
├── sugar_agent/          # Python 后端
│   ├── main.py           # FastAPI 路由入口
│   ├── agent.py          # ReAct Agent 核心逻辑
│   ├── database.py       # SQLite 数据库操作
│   ├── models.py         # Pydantic 数据模型
│   ├── tavily_search.py  # 联网搜索封装
│   ├── config.py         # 环境变量加载
│   ├── requirements.txt  # Python 依赖
│   └── sugar_control.db  # 初始食物知识库（68 条，可扩充）
│
├── sugar_control_app/    # Flutter 前端
│   ├── lib/
│   │   ├── main.dart
│   │   ├── screens/      # 聊天、统计、设置、相机界面
│   │   ├── services/     # API 调用、购物监控服务
│   │   └── theme/
│   └── android/          # Android 原生代码（无障碍服务）
│
├── .env.example          # 环境变量模板
└── .gitignore
```

---

## 部署指南

### 1. 申请 API Key

运行本项目需要两个 API Key：

- **Dashscope（必须）**：阿里云百炼平台，用于驱动 AI 对话
  - 注册地址：https://dashscope.console.aliyun.com/
  - 新用户有免费额度

- **Tavily（可选）**：联网搜索，用于查询知识库里没有、模型本身知识也未涉及的新食品
  - 注册地址：https://tavily.com/
  - 免费版每月 1000 次调用，足够个人使用
  - 此功能为本地知识库和模型知识均未涉及某新食品时的兜底选项，实际使用效果较差，联网搜索返回结果中关于新食物营养数据的回答通常较少甚至没有。如有条件此功能可升级为调用薄荷健康等权威食品数据库 API（需自费购买）

### 2. 配置环境变量

```bash
cd sugar_agent
cp ../.env.example .env   # Windows: copy .env.example .env
```

编辑 `.env`，填入你的 Key：

```
DASHSCOPE_API_KEY=sk-你的key
TAVILY_API_KEY=tvly-dev-你的key
```

### 3. 启动后端

```bash
cd sugar_agent
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000
```

> 建议部署到公网服务器（云服务器 / Render / Railway 等），或在局域网内运行后将手机和电脑连同一 WiFi。

### 4. 配置前端接口地址

打开 [sugar_control_app/lib/services/api_service.dart](sugar_control_app/lib/services/api_service.dart)，将第 6 行的地址改为你的后端地址：

```dart
// 局域网（手机和电脑同一 WiFi）
const _base = 'http://192.168.x.x:8000';

// 公网服务器
const _base = 'http://你的服务器IP:8000';

// Android 模拟器调试
const _base = 'http://10.0.2.2:8000';
```

### 5. 编译安装 App

```bash
cd sugar_control_app
flutter pub get
flutter run          # 调试运行
flutter build apk    # 打包 APK
```

> 需要提前安装 Flutter SDK：https://docs.flutter.dev/get-started/install

### 6. 开启必要权限

App 首次运行后，在手机设置中手动开启：
- **无障碍服务**（用于购物监控预警功能）
- **悬浮窗权限**（用于显示高糖预警弹窗）

---

## 知识库说明

`sugar_control.db` 中预置了 68 条常见食品的糖分数据（奶茶、甜品、水果等），**仅供调试参考，数据不保证完全准确**。

扩充知识库的方式：
- **自动积累**：正常使用 App 查询食物时，AI 会自动将查询结果写入知识库
- **手动导入**：直接用 SQLite 工具（如 DB Browser for SQLite）编辑 `sugar_control.db` 中的 `food_knowledge` 表

知识库数据越丰富，AI 回答越快、越准确（减少联网搜索次数）。

---

## 主要依赖

**后端：**
- [FastAPI](https://fastapi.tiangolo.com/) — Web 框架
- [OpenAI Python SDK](https://github.com/openai/openai-python) — 兼容 Dashscope API
- [Tavily Python](https://github.com/tavily-ai/tavily-python) — 联网搜索

**前端：**
- [Flutter](https://flutter.dev/) — 跨平台 UI 框架
- [flutter_markdown_plus](https://pub.dev/packages/flutter_markdown_plus) — Markdown 渲染
- [http](https://pub.dev/packages/http) — HTTP 客户端

---

## License

MIT
