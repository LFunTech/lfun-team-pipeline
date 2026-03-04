# RAG 客服问答服务 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 构建一个基于 LangChain + Chroma 的 RAG 客服问答 FastAPI 服务，支持多数据源摄入和多 LLM 后端切换。

**Architecture:** FastAPI 提供 /ingest、/query、/sources 三个端点；Ingest Pipeline 负责加载文档、切分、向量化后存入 Chroma；Query Pipeline 负责向量检索 + LLM 生成答案。LLM 后端通过配置文件在 Ollama/Qwen/DeepSeek 之间切换，使用 OpenAI 兼容接口。

**Tech Stack:** Python 3.11+, FastAPI, LangChain, Chroma, BAAI/bge-m3, pytest, pyyaml, python-dotenv

---

## 前置准备

新建项目目录（不在 team-creator 内，独立项目）：

```bash
mkdir -p /home/min/repos/rag-service
cd /home/min/repos/rag-service
git init
python3 -m venv .venv
source .venv/bin/activate
```

---

### Task 1: 项目骨架与依赖

**Files:**
- Create: `requirements.txt`
- Create: `config.yaml`
- Create: `.env.example`
- Create: `.gitignore`

**Step 1: 创建 requirements.txt**

```
fastapi==0.115.0
uvicorn[standard]==0.30.0
langchain==0.3.0
langchain-community==0.3.0
langchain-chroma==0.1.4
langchain-openai==0.2.0
chromadb==0.5.0
sentence-transformers==3.1.0
pyyaml==6.0.2
python-dotenv==1.0.1
sqlalchemy==2.0.35
beautifulsoup4==4.12.3
requests==2.32.3
pytest==8.3.0
pytest-asyncio==0.24.0
httpx==0.27.0
```

**Step 2: 创建 config.yaml**

```yaml
llm:
  default: "ollama"
  providers:
    ollama:
      base_url: "http://localhost:11434/v1"
      api_key: "ollama"
      model: "qwen2.5:7b"
    qwen:
      base_url: "https://dashscope.aliyuncs.com/compatible-mode/v1"
      api_key: "${QWEN_API_KEY}"
      model: "qwen-plus"
    deepseek:
      base_url: "https://api.deepseek.com/v1"
      api_key: "${DEEPSEEK_API_KEY}"
      model: "deepseek-chat"

embedding:
  model: "BAAI/bge-m3"
  device: "cpu"

vector_store:
  persist_dir: "./chroma_db"

ingest:
  chunk_size: 1000
  chunk_overlap: 200
```

**Step 3: 创建 .env.example**

```
QWEN_API_KEY=your_key_here
DEEPSEEK_API_KEY=your_key_here
```

**Step 4: 创建 .gitignore**

```
.venv/
__pycache__/
*.pyc
.env
chroma_db/
.pytest_cache/
```

**Step 5: 安装依赖**

```bash
pip install -r requirements.txt
```

**Step 6: 创建目录结构**

```bash
mkdir -p src/api src/pipeline src/adapters tests
touch src/__init__.py src/api/__init__.py src/pipeline/__init__.py src/adapters/__init__.py
```

**Step 7: Commit**

```bash
git add .
git commit -m "chore: project scaffold with dependencies and config"
```

---

### Task 2: 配置加载模块

**Files:**
- Create: `src/config.py`
- Create: `tests/test_config.py`

**Step 1: 写失败测试**

```python
# tests/test_config.py
import os
import pytest
from src.config import load_config, get_llm_config, get_embedding_config

def test_load_config_returns_dict():
    cfg = load_config("config.yaml")
    assert "llm" in cfg
    assert "embedding" in cfg
    assert "vector_store" in cfg

def test_get_llm_config_default():
    cfg = load_config("config.yaml")
    llm_cfg = get_llm_config(cfg)
    assert "base_url" in llm_cfg
    assert "model" in llm_cfg

def test_get_llm_config_specific_provider():
    cfg = load_config("config.yaml")
    llm_cfg = get_llm_config(cfg, provider="deepseek")
    assert llm_cfg["model"] == "deepseek-chat"

def test_env_var_substitution(monkeypatch):
    monkeypatch.setenv("QWEN_API_KEY", "test_key_123")
    cfg = load_config("config.yaml")
    llm_cfg = get_llm_config(cfg, provider="qwen")
    assert llm_cfg["api_key"] == "test_key_123"
```

**Step 2: 运行确认失败**

```bash
pytest tests/test_config.py -v
```
Expected: FAIL with `ModuleNotFoundError`

**Step 3: 实现 src/config.py**

```python
import os
import re
import yaml
from dotenv import load_dotenv

load_dotenv()


def _expand_env_vars(value: str) -> str:
    """将 ${VAR_NAME} 替换为环境变量值。"""
    if not isinstance(value, str):
        return value
    return re.sub(r'\$\{(\w+)\}', lambda m: os.environ.get(m.group(1), m.group(0)), value)


def _expand_dict(d: dict) -> dict:
    """递归展开字典中的所有环境变量。"""
    result = {}
    for k, v in d.items():
        if isinstance(v, dict):
            result[k] = _expand_dict(v)
        elif isinstance(v, str):
            result[k] = _expand_env_vars(v)
        else:
            result[k] = v
    return result


def load_config(path: str = "config.yaml") -> dict:
    with open(path, "r") as f:
        raw = yaml.safe_load(f)
    return _expand_dict(raw)


def get_llm_config(cfg: dict, provider: str | None = None) -> dict:
    provider = provider or cfg["llm"]["default"]
    return cfg["llm"]["providers"][provider]


def get_embedding_config(cfg: dict) -> dict:
    return cfg["embedding"]
```

**Step 4: 运行确认通过**

```bash
pytest tests/test_config.py -v
```
Expected: 4 PASSED

**Step 5: Commit**

```bash
git add src/config.py tests/test_config.py
git commit -m "feat: config loader with env var substitution"
```

---

### Task 3: LLM 适配器

**Files:**
- Create: `src/adapters/llm.py`
- Create: `tests/test_llm_adapter.py`

**Step 1: 写失败测试**

```python
# tests/test_llm_adapter.py
from unittest.mock import MagicMock, patch
from src.adapters.llm import build_llm
from src.config import load_config


def test_build_llm_ollama():
    cfg = load_config("config.yaml")
    llm = build_llm(cfg, provider="ollama")
    assert llm is not None
    # ChatOpenAI 兼容接口，检查 model_name
    assert "qwen" in llm.model_name.lower() or llm.model_name == "qwen2.5:7b"


def test_build_llm_returns_chat_model():
    cfg = load_config("config.yaml")
    llm = build_llm(cfg, provider="ollama")
    # 验证有 invoke 方法（LangChain BaseLanguageModel 接口）
    assert callable(getattr(llm, "invoke", None))


def test_build_llm_unknown_provider_raises():
    cfg = load_config("config.yaml")
    import pytest
    with pytest.raises(KeyError):
        build_llm(cfg, provider="nonexistent")
```

**Step 2: 运行确认失败**

```bash
pytest tests/test_llm_adapter.py -v
```

**Step 3: 实现 src/adapters/llm.py**

```python
from langchain_openai import ChatOpenAI
from src.config import get_llm_config


def build_llm(cfg: dict, provider: str | None = None) -> ChatOpenAI:
    """根据配置构建 LangChain ChatOpenAI 兼容的 LLM 实例。"""
    llm_cfg = get_llm_config(cfg, provider)
    return ChatOpenAI(
        base_url=llm_cfg["base_url"],
        api_key=llm_cfg["api_key"],
        model=llm_cfg["model"],
        temperature=0.1,
        max_tokens=1024,
    )
```

**Step 4: 运行确认通过**

```bash
pytest tests/test_llm_adapter.py -v
```
Expected: 3 PASSED

**Step 5: Commit**

```bash
git add src/adapters/llm.py tests/test_llm_adapter.py
git commit -m "feat: LLM adapter supporting Ollama/Qwen/DeepSeek via OpenAI-compat"
```

---

### Task 4: 嵌入模型适配器

**Files:**
- Create: `src/adapters/embeddings.py`
- Create: `tests/test_embeddings.py`

**Step 1: 写失败测试**

```python
# tests/test_embeddings.py
from src.adapters.embeddings import build_embeddings
from src.config import load_config


def test_build_embeddings_returns_instance():
    cfg = load_config("config.yaml")
    embeddings = build_embeddings(cfg)
    assert embeddings is not None


def test_embeddings_can_embed_text():
    cfg = load_config("config.yaml")
    embeddings = build_embeddings(cfg)
    vectors = embeddings.embed_documents(["如何退款？"])
    assert len(vectors) == 1
    assert len(vectors[0]) > 100  # bge-m3 输出 1024 维
```

**Step 2: 运行确认失败**

```bash
pytest tests/test_embeddings.py -v
```

**Step 3: 实现 src/adapters/embeddings.py**

```python
from langchain_community.embeddings import HuggingFaceEmbeddings
from src.config import get_embedding_config


def build_embeddings(cfg: dict) -> HuggingFaceEmbeddings:
    """构建本地嵌入模型（BAAI/bge-m3）。"""
    emb_cfg = get_embedding_config(cfg)
    return HuggingFaceEmbeddings(
        model_name=emb_cfg["model"],
        model_kwargs={"device": emb_cfg.get("device", "cpu")},
        encode_kwargs={"normalize_embeddings": True},
    )
```

**Step 4: 运行确认通过**（首次运行会下载模型，约 1GB，需等待）

```bash
pytest tests/test_embeddings.py -v
```
Expected: 2 PASSED

**Step 5: Commit**

```bash
git add src/adapters/embeddings.py tests/test_embeddings.py
git commit -m "feat: embedding adapter using BAAI/bge-m3"
```

---

### Task 5: 数据源加载器

**Files:**
- Create: `src/adapters/loaders.py`
- Create: `tests/test_loaders.py`
- Create: `tests/fixtures/sample_faq.csv`

**Step 1: 创建测试 fixture**

```csv
# tests/fixtures/sample_faq.csv
question,answer
如何退款？,请在订单页面点击申请退款按钮，填写退款原因后提交。
配送时间多久？,标准配送 3-5 个工作日，加急配送 1-2 个工作日。
支持哪些支付方式？,支持微信支付、支付宝、银行卡等主流支付方式。
```

**Step 2: 写失败测试**

```python
# tests/test_loaders.py
import pytest
from src.adapters.loaders import load_documents


def test_load_file_csv():
    docs = load_documents(
        source_type="file",
        source_config={"path": "tests/fixtures/sample_faq.csv"},
    )
    assert len(docs) >= 1
    assert hasattr(docs[0], "page_content")


def test_load_file_txt(tmp_path):
    f = tmp_path / "test.txt"
    f.write_text("这是一段测试文本，用于验证 txt 加载。")
    docs = load_documents(
        source_type="file",
        source_config={"path": str(f)},
    )
    assert len(docs) >= 1
    assert "测试文本" in docs[0].page_content


def test_load_unsupported_type_raises():
    with pytest.raises(ValueError, match="unsupported source_type"):
        load_documents(source_type="ftp", source_config={})
```

**Step 3: 运行确认失败**

```bash
pytest tests/test_loaders.py -v
```

**Step 4: 实现 src/adapters/loaders.py**

```python
from pathlib import Path
from typing import Any
from langchain_core.documents import Document
from langchain_community.document_loaders import (
    CSVLoader,
    TextLoader,
    UnstructuredMarkdownLoader,
    WebBaseLoader,
)


def load_documents(source_type: str, source_config: dict[str, Any]) -> list[Document]:
    """根据数据源类型加载文档列表。"""
    if source_type == "file":
        return _load_file(source_config["path"])
    elif source_type == "web":
        loader = WebBaseLoader(source_config["urls"])
        return loader.load()
    elif source_type == "database":
        return _load_database(source_config)
    else:
        raise ValueError(f"unsupported source_type: {source_type}")


def _load_file(path: str) -> list[Document]:
    suffix = Path(path).suffix.lower()
    if suffix == ".csv":
        loader = CSVLoader(path)
    elif suffix in (".md", ".markdown"):
        loader = UnstructuredMarkdownLoader(path)
    else:
        loader = TextLoader(path, encoding="utf-8")
    return loader.load()


def _load_database(config: dict) -> list[Document]:
    """从数据库加载文档，将每行转换为 Document。"""
    from sqlalchemy import create_engine, text
    engine = create_engine(config["dsn"])
    with engine.connect() as conn:
        rows = conn.execute(text(config["query"])).fetchall()
    docs = []
    for i, row in enumerate(rows):
        content = " | ".join(str(v) for v in row)
        docs.append(Document(page_content=content, metadata={"row": i, "source": "database"}))
    return docs
```

**Step 5: 运行确认通过**

```bash
pytest tests/test_loaders.py -v
```
Expected: 3 PASSED

**Step 6: Commit**

```bash
git add src/adapters/loaders.py tests/test_loaders.py tests/fixtures/
git commit -m "feat: document loaders for file/web/database sources"
```

---

### Task 6: Ingest Pipeline

**Files:**
- Create: `src/pipeline/ingest.py`
- Create: `tests/test_pipeline_ingest.py`

**Step 1: 写失败测试**

```python
# tests/test_pipeline_ingest.py
import pytest
from unittest.mock import MagicMock, patch
from src.pipeline.ingest import run_ingest


def test_run_ingest_returns_chunk_count():
    mock_embeddings = MagicMock()
    mock_embeddings.embed_documents.return_value = [[0.1] * 10]

    with patch("src.pipeline.ingest.Chroma") as mock_chroma:
        mock_store = MagicMock()
        mock_chroma.from_documents.return_value = mock_store

        result = run_ingest(
            source_type="file",
            source_config={"path": "tests/fixtures/sample_faq.csv"},
            collection="test_col",
            embeddings=mock_embeddings,
            persist_dir="./test_chroma_db",
        )

    assert "chunks_count" in result
    assert result["chunks_count"] > 0
    assert result["collection"] == "test_col"


def test_run_ingest_calls_chroma_from_documents():
    mock_embeddings = MagicMock()

    with patch("src.pipeline.ingest.Chroma") as mock_chroma:
        mock_chroma.from_documents.return_value = MagicMock()
        run_ingest(
            source_type="file",
            source_config={"path": "tests/fixtures/sample_faq.csv"},
            collection="test_col",
            embeddings=mock_embeddings,
            persist_dir="./test_chroma_db",
        )
        assert mock_chroma.from_documents.called
```

**Step 2: 运行确认失败**

```bash
pytest tests/test_pipeline_ingest.py -v
```

**Step 3: 实现 src/pipeline/ingest.py**

```python
from typing import Any
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain_chroma import Chroma
from src.adapters.loaders import load_documents


def run_ingest(
    source_type: str,
    source_config: dict[str, Any],
    collection: str,
    embeddings,
    persist_dir: str,
    chunk_size: int = 1000,
    chunk_overlap: int = 200,
) -> dict:
    """摄入数据源，切分后存入 Chroma 向量库。返回摄入统计信息。"""
    docs = load_documents(source_type, source_config)

    splitter = RecursiveCharacterTextSplitter(
        chunk_size=chunk_size,
        chunk_overlap=chunk_overlap,
    )
    chunks = splitter.split_documents(docs)

    Chroma.from_documents(
        documents=chunks,
        embedding=embeddings,
        collection_name=collection,
        persist_directory=persist_dir,
    )

    return {
        "collection": collection,
        "chunks_count": len(chunks),
        "source_docs": len(docs),
    }
```

**Step 4: 运行确认通过**

```bash
pytest tests/test_pipeline_ingest.py -v
```
Expected: 2 PASSED

**Step 5: Commit**

```bash
git add src/pipeline/ingest.py tests/test_pipeline_ingest.py
git commit -m "feat: ingest pipeline with chunking and Chroma storage"
```

---

### Task 7: Query Pipeline

**Files:**
- Create: `src/pipeline/query.py`
- Create: `tests/test_pipeline_query.py`

**Step 1: 写失败测试**

```python
# tests/test_pipeline_query.py
from unittest.mock import MagicMock, patch
from langchain_core.documents import Document
from src.pipeline.query import run_query


def _make_mock_retriever(docs):
    retriever = MagicMock()
    retriever.invoke.return_value = docs
    return retriever


def _make_mock_llm(answer: str):
    llm = MagicMock()
    msg = MagicMock()
    msg.content = answer
    llm.invoke.return_value = msg
    return llm


def test_run_query_returns_answer():
    mock_docs = [
        Document(page_content="退款需要在订单页面申请。", metadata={"source": "faq.csv"}),
    ]
    mock_retriever = _make_mock_retriever(mock_docs)
    mock_llm = _make_mock_llm("您可以在订单页面申请退款。")

    with patch("src.pipeline.query.Chroma") as mock_chroma_cls:
        mock_store = MagicMock()
        mock_store.as_retriever.return_value = mock_retriever
        mock_chroma_cls.return_value = mock_store

        result = run_query(
            question="如何退款？",
            collection="faq_v1",
            embeddings=MagicMock(),
            llm=mock_llm,
            persist_dir="./test_chroma_db",
            top_k=3,
        )

    assert "answer" in result
    assert "sources" in result
    assert isinstance(result["sources"], list)


def test_run_query_sources_contain_content():
    mock_docs = [
        Document(page_content="退款需要在订单页面申请。", metadata={"source": "faq.csv"}),
    ]
    mock_retriever = _make_mock_retriever(mock_docs)
    mock_llm = _make_mock_llm("请在订单页面点击退款。")

    with patch("src.pipeline.query.Chroma") as mock_chroma_cls:
        mock_store = MagicMock()
        mock_store.as_retriever.return_value = mock_retriever
        mock_chroma_cls.return_value = mock_store

        result = run_query(
            question="退款",
            collection="faq_v1",
            embeddings=MagicMock(),
            llm=mock_llm,
            persist_dir="./test_chroma_db",
            top_k=3,
        )

    assert len(result["sources"]) == 1
    assert "content" in result["sources"][0]
```

**Step 2: 运行确认失败**

```bash
pytest tests/test_pipeline_query.py -v
```

**Step 3: 实现 src/pipeline/query.py**

```python
import time
from langchain_chroma import Chroma
from langchain_core.prompts import ChatPromptTemplate

PROMPT_TEMPLATE = """\
你是一个客服助手，请根据以下参考资料回答用户问题。
如果参考资料中没有相关信息，请如实说明。

参考资料：
{context}

用户问题：{question}

请用简洁友好的中文回答："""


def run_query(
    question: str,
    collection: str,
    embeddings,
    llm,
    persist_dir: str,
    top_k: int = 5,
) -> dict:
    """检索相关文档并用 LLM 生成回答。"""
    start = time.time()

    store = Chroma(
        collection_name=collection,
        embedding_function=embeddings,
        persist_directory=persist_dir,
    )
    retriever = store.as_retriever(search_kwargs={"k": top_k})
    docs = retriever.invoke(question)

    context = "\n\n".join(d.page_content for d in docs)
    prompt = ChatPromptTemplate.from_template(PROMPT_TEMPLATE)
    chain = prompt | llm
    response = chain.invoke({"context": context, "question": question})

    latency_ms = int((time.time() - start) * 1000)

    return {
        "answer": response.content,
        "sources": [
            {"content": d.page_content, "source": d.metadata.get("source", "")}
            for d in docs
        ],
        "latency_ms": latency_ms,
    }
```

**Step 4: 运行确认通过**

```bash
pytest tests/test_pipeline_query.py -v
```
Expected: 2 PASSED

**Step 5: Commit**

```bash
git add src/pipeline/query.py tests/test_pipeline_query.py
git commit -m "feat: query pipeline with retrieval and LLM generation"
```

---

### Task 8: FastAPI 路由

**Files:**
- Create: `src/api/ingest.py`
- Create: `src/api/query.py`
- Create: `src/api/sources.py`
- Create: `tests/test_api.py`

**Step 1: 写失败测试**

```python
# tests/test_api.py
import pytest
from unittest.mock import patch, MagicMock
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)


def test_health_check():
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


def test_ingest_file_returns_job_info():
    with patch("src.api.ingest.run_ingest") as mock_ingest:
        mock_ingest.return_value = {
            "collection": "faq_v1",
            "chunks_count": 42,
            "source_docs": 10,
        }
        resp = client.post("/ingest", json={
            "source_type": "file",
            "source_config": {"path": "tests/fixtures/sample_faq.csv"},
            "collection": "faq_v1",
        })
    assert resp.status_code == 200
    data = resp.json()
    assert data["chunks_count"] == 42
    assert data["collection"] == "faq_v1"


def test_query_returns_answer():
    with patch("src.api.query.run_query") as mock_query:
        mock_query.return_value = {
            "answer": "您可以在订单页面申请退款。",
            "sources": [{"content": "退款政策...", "source": "faq.csv"}],
            "latency_ms": 800,
        }
        resp = client.post("/query", json={
            "question": "如何退款？",
            "collection": "faq_v1",
        })
    assert resp.status_code == 200
    data = resp.json()
    assert "answer" in data
    assert "sources" in data
    assert "latency_ms" in data


def test_sources_returns_list():
    with patch("src.api.sources.list_collections") as mock_list:
        mock_list.return_value = [{"name": "faq_v1", "count": 100}]
        resp = client.get("/sources")
    assert resp.status_code == 200
    assert isinstance(resp.json(), list)
```

**Step 2: 运行确认失败**

```bash
pytest tests/test_api.py -v
```

**Step 3: 实现路由文件**

```python
# src/api/ingest.py
from fastapi import APIRouter, Depends
from pydantic import BaseModel
from typing import Any
from src.pipeline.ingest import run_ingest
from src.adapters.embeddings import build_embeddings
from src.config import load_config

router = APIRouter()


class IngestRequest(BaseModel):
    source_type: str
    source_config: dict[str, Any]
    collection: str = "default"


@router.post("/ingest")
def ingest(req: IngestRequest):
    cfg = load_config()
    embeddings = build_embeddings(cfg)
    result = run_ingest(
        source_type=req.source_type,
        source_config=req.source_config,
        collection=req.collection,
        embeddings=embeddings,
        persist_dir=cfg["vector_store"]["persist_dir"],
        chunk_size=cfg["ingest"]["chunk_size"],
        chunk_overlap=cfg["ingest"]["chunk_overlap"],
    )
    return result
```

```python
# src/api/query.py
from fastapi import APIRouter
from pydantic import BaseModel
from typing import Optional
from src.pipeline.query import run_query
from src.adapters.embeddings import build_embeddings
from src.adapters.llm import build_llm
from src.config import load_config

router = APIRouter()


class QueryRequest(BaseModel):
    question: str
    collection: str = "default"
    top_k: int = 5
    llm: Optional[str] = None


@router.post("/query")
def query(req: QueryRequest):
    cfg = load_config()
    embeddings = build_embeddings(cfg)
    llm = build_llm(cfg, provider=req.llm)
    result = run_query(
        question=req.question,
        collection=req.collection,
        embeddings=embeddings,
        llm=llm,
        persist_dir=cfg["vector_store"]["persist_dir"],
        top_k=req.top_k,
    )
    return result
```

```python
# src/api/sources.py
from fastapi import APIRouter
import chromadb
from src.config import load_config

router = APIRouter()


def list_collections() -> list[dict]:
    cfg = load_config()
    client = chromadb.PersistentClient(path=cfg["vector_store"]["persist_dir"])
    collections = client.list_collections()
    return [{"name": c.name, "count": c.count()} for c in collections]


@router.get("/sources")
def sources():
    return list_collections()
```

**Step 4: 创建 main.py**

```python
# main.py
from fastapi import FastAPI
from src.api.ingest import router as ingest_router
from src.api.query import router as query_router
from src.api.sources import router as sources_router

app = FastAPI(title="RAG FAQ Service", version="0.1.0")

app.include_router(ingest_router)
app.include_router(query_router)
app.include_router(sources_router)


@app.get("/health")
def health():
    return {"status": "ok"}
```

**Step 5: 运行确认通过**

```bash
pytest tests/test_api.py -v
```
Expected: 4 PASSED

**Step 6: Commit**

```bash
git add src/api/ main.py tests/test_api.py
git commit -m "feat: FastAPI routes for ingest, query, and sources"
```

---

### Task 9: 全量测试 & 启动验证

**Step 1: 运行所有测试**

```bash
pytest tests/ -v --tb=short
```
Expected: 所有测试 PASS，无 FAIL

**Step 2: 启动服务验证**

```bash
uvicorn main:app --reload --port 8000
```

**Step 3: 手动验收 — 摄入 FAQ**

新开终端：
```bash
curl -X POST http://localhost:8000/ingest \
  -H "Content-Type: application/json" \
  -d '{"source_type":"file","source_config":{"path":"tests/fixtures/sample_faq.csv"},"collection":"faq_v1"}'
```
Expected: `{"collection":"faq_v1","chunks_count":...}`

**Step 4: 手动验收 — 问答**

```bash
curl -X POST http://localhost:8000/query \
  -H "Content-Type: application/json" \
  -d '{"question":"如何退款？","collection":"faq_v1"}'
```
Expected: 返回含 `answer` 和 `sources` 的 JSON，`latency_ms` < 2000

**Step 5: Commit**

```bash
git add .
git commit -m "test: full test suite passes, service verified end-to-end"
```

---

## 验收清单

- [ ] 所有单测通过（`pytest tests/ -v`）
- [ ] `/health` 返回 200
- [ ] `/ingest` 能摄入 CSV 文件
- [ ] `/query` 能返回答案和来源引用
- [ ] `/sources` 能列出集合
- [ ] 延迟 < 2 秒（本地 Ollama）
- [ ] 切换 LLM 只需改 config.yaml 或请求参数
