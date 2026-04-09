import os
from dotenv import load_dotenv, find_dotenv

# Search current dir and all parent dirs for .env
load_dotenv(find_dotenv(usecwd=True))

DASHSCOPE_API_KEY = os.getenv("DASHSCOPE_API_KEY", "")
TAVILY_API_KEY = os.getenv("TAVILY_API_KEY", "")

DATABASE_PATH = os.getenv("DATABASE_PATH", "sugar_control.db")
