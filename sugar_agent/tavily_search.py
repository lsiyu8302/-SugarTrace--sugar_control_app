from tavily import TavilyClient
from config import TAVILY_API_KEY


def search_food_sugar_info(food_name: str) -> str:
    """Search the web for sugar/nutrition info about a food item."""
    if not TAVILY_API_KEY:
        return f"（Tavily API Key 未配置，无法联网搜索 {food_name} 的含糖量信息）"

    client = TavilyClient(api_key=TAVILY_API_KEY)
    query = f"{food_name} 含糖量 升糖指数 热量 营养成分"
    try:
        result = client.search(query=query, max_results=5, search_depth="basic")
        snippets = [r.get("content", "") for r in result.get("results", [])]
        return "\n\n".join(snippets) if snippets else "未找到相关信息"
    except Exception as e:
        return f"搜索失败：{e}"
