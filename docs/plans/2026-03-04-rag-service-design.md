# LLM RAG 客服问答服务 — 设计文档

**日期**：2026-03-04
**场景**：客服/产品 FAQ 问答（面向终端用户）
**规模**：小规模，< 100 QPS，单机部署

---

## 技术选型

| 组件 | 选型 | 理由 |
|------|------|------|
| Web 框架 | FastAPI | 异步、高性能、自动文档 |
| RAG 框架 | LangChain | 成熟生态，混合数据源支持好，多 LLM 切换简单 |
| 向量数据库 | Chroma | 轻量嵌入式，无需额外服务，本地持久化 |
| 嵌入模型 | BAAI/bge-m3 | 中文效果好，本地运行 |
| LLM 后端 | Ollama / Qwen API / DeepSeek API | 配置文件切换，零代码改动 |

---

## 整体架构

```
┌─────────────────────────────────────────────────┐
│                   FastAPI 服务                    │
│                                                   │
│  /ingest   ── 数据摄入 API                        │
│  /query    ── 问答 API                            │
│  /sources  ── 数据源管理 API                      │
└──────────┬──────────────────────┬────────────────┘
           │                      │
    ┌──────▼──────┐        ┌──────▼──────┐
    │  Ingest     │        │  Query      │
    │  Pipeline   │        │  Pipeline   │
    │             │        │             │
    │ 加载文档     │        │ 向量检索     │
    │ 切分分块     │        │ 重排序      │
    │ 生成向量     │        │ LLM 生成    │
    └──────┬──────┘        └──────┬──────┘
           │                      │
    ┌──────▼──────────────────────▼──────┐
    │           Chroma 向量库             │
    │     (本地持久化, 按 source 分集合)   │
    └────────────────────────────────────┘
           │                      │
    ┌──────▼──────┐        ┌──────▼──────┐
    │ 数据源适配器  │        │ LLM 适配器  │
    │             │        │             │
    │ - 文件       │        │ - Ollama    │
    │ - 数据库     │        │ - Qwen API  │
    │ - 网页爬取   │        │ - DeepSeek  │
    └─────────────┘        └─────────────┘
```

**摄入流程**：数据源 → 加载 → 切分（1000 tokens, 200 overlap）→ 向量化 → 存入 Chroma

**问答流程**：用户问题 → 向量检索 Top-K → LLM 生成答案 → 返回答案 + 来源引用

---

## API 接口

### `POST /ingest`

```json
// 请求
{
  "source_type": "file" | "database" | "web",
  "source_config": {
    // file:     {"path": "/data/faq.csv"}
    // database: {"dsn": "mysql://...", "query": "SELECT question, answer FROM faq"}
    // web:      {"urls": ["https://..."]}
  },
  "collection": "faq_v1"
}

// 响应
{
  "job_id": "abc123",
  "status": "processing",
  "chunks_count": 342
}
```

### `POST /query`

```json
// 请求
{
  "question": "如何退款？",
  "collection": "faq_v1",
  "top_k": 5,
  "llm": "ollama"
}

// 响应
{
  "answer": "您可以在订单页面点击...",
  "sources": [
    {"content": "退款政策：...", "score": 0.92, "source": "faq.csv:row_12"}
  ],
  "latency_ms": 1240
}
```

### `GET /sources`

列出所有已摄入的集合及文档数量。

---

## LLM 适配器 & 配置

```yaml
# config.yaml
llm:
  default: "ollama"
  providers:
    ollama:
      base_url: "http://localhost:11434"
      model: "qwen2.5:7b"
    qwen:
      api_key: "${QWEN_API_KEY}"
      model: "qwen-plus"
    deepseek:
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

LangChain 的 `ChatOpenAI` 兼容接口直接对接 Ollama、Qwen、DeepSeek（均提供 OpenAI 兼容端点），适配器仅需根据 `provider` 选择不同的 `base_url` 和 `api_key`。

---

## 项目结构

```
rag-service/
├── config.yaml
├── .env
├── requirements.txt
├── main.py
├── src/
│   ├── api/
│   │   ├── ingest.py
│   │   ├── query.py
│   │   └── sources.py
│   ├── pipeline/
│   │   ├── ingest.py
│   │   └── query.py
│   ├── adapters/
│   │   ├── llm.py
│   │   ├── loaders.py
│   │   └── embeddings.py
│   └── config.py
└── tests/
    ├── test_ingest.py
    ├── test_query.py
    └── test_api.py
```

---

## 测试策略

- **单测**：pytest + mock LLM（避免 API 费用），mock Chroma（内存模式）
- **集成测试**：真实 Chroma（内存模式）+ mock LLM，验证全链路
- **手动验收**：准备 10 条典型 FAQ，验证召回率和答案质量

---

## 延迟目标

- 目标：< 2 秒端到端响应
- 嵌入向量化在摄入阶段完成，查询时只做向量检索（< 50ms）+ LLM 生成（< 1.5s）
