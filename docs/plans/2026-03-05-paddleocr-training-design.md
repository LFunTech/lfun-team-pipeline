# PaddleOCR 手写体识别训练系统 — 设计文档

**日期**：2026-03-05
**状态**：已批准
**用途**：team-creator v6 流水线第四次 Demo

---

## 1. 项目背景

开发一套完整的 PaddleOCR 手写体识别训练系统，支持中英文及数学/物理/化学相关手写内容识别（含 LaTeX 公式输出）。同时作为 team-creator 多角色软件交付流水线 v6 的测试项目。

**目标用户：**
- 研究人员/教师：上传样本、标注数据、提交训练、导出模型
- 学生/考生：拍照上传，在线识别手写内容并获得结构化文字/LaTeX 结果
- 平台运营方：管理数据采集 → 标注 → 训练 → 部署 → 推理完整闭环

**部署环境**：双 V100 32G GPU 服务器，Docker Compose

---

## 2. 整体架构

```
                    ┌─────────────────────────────────────┐
                    │           API Gateway (Nginx)         │
                    │         localhost:80                  │
                    └─────┬──────┬──────┬──────┬──────┬───┘
                          │      │      │      │      │
              ┌───────────┘  ┌───┘  ┌───┘  ┌───┘  ┌───┘
              ▼              ▼      ▼      ▼      ▼
        annotation-    dataset-  training- inference- model-
         service       service   service   service   registry
         :8001         :8002     :8003     :8004     :8005
              │              │      │      │
              └──────┬────────┘      │      │
                     ▼               ▼      ▼
                PostgreSQL         V100#1  V100#2
                  MinIO
                  Redis (job queue)
```

### 服务清单

| 服务 | 端口 | 职责 | GPU |
|------|------|------|-----|
| `annotation-service` | 8001 | 图片上传、画框标注、标签管理 | 无 |
| `dataset-service` | 8002 | 数据集 CRUD、版本管理、格式导出 | 无 |
| `training-service` | 8003 | PaddleOCR 训练任务提交/监控/导出 | V100 #1 |
| `inference-service` | 8004 | OCR 推理 + pix2tex 公式识别 | V100 #2 |
| `model-registry` | 8005 | 模型版本管理、上线/下线 | 无 |
| `frontend` | 3000 | React SPA（三用户角色视图） | 无 |
| `api-gateway` | 80 | Nginx 路由 + 静态资源 | 无 |

### 共享基础设施

- **PostgreSQL**：所有元数据持久化
- **MinIO**：图片、数据集、模型文件对象存储
- **Redis**：Celery 训练任务队列
- **Docker Compose**：单机编排，GPU device 显式挂载

---

## 3. 数据模型

### PostgreSQL 主要表

```sql
users           (id, role, email, created_at)
                role: researcher | student | operator

datasets        (id, name, owner_id, status, category, created_at)
                category: zh | en | math | physics | chemistry | mixed

images          (id, dataset_id, file_path, width, height, status)
                status: uploaded | annotated | exported

annotations     (id, image_id, bbox_x, bbox_y, bbox_w, bbox_h,
                 label_text, label_type, created_at)
                label_type: text | formula | diagram

training_jobs   (id, dataset_id, model_type, status, config_json,
                 gpu_id, started_at, finished_at, error_msg)
                status: queued | running | success | failed

models          (id, job_id, name, version, accuracy, file_path,
                 is_active, created_at)

inference_logs  (id, model_id, user_id, input_path, result_json,
                 latency_ms, created_at)
```

### MinIO Bucket 结构

```
ocr-images/      ← 上传的原始图片
ocr-datasets/    ← 打包导出的训练集
ocr-models/      ← 训练产出的模型文件
```

---

## 4. 服务间 REST 契约

```
# 标注 → 数据集
POST   /api/annotations              annotation-service
GET    /api/datasets/{id}/images     dataset-service

# 数据集 → 训练
POST   /api/datasets/{id}/export     dataset-service → 触发打包
POST   /api/jobs                     training-service（提交训练）
GET    /api/jobs/{id}/status         训练进度轮询
GET    /api/jobs/{id}/logs           训练日志流

# 训练 → 模型仓库
POST   /api/models                   model-registry（注册模型）
POST   /api/models/{id}/activate     上线模型

# 推理
POST   /api/inference/ocr            文字识别
POST   /api/inference/formula        手写公式 → LaTeX
GET    /api/inference/health         健康检查

# 通用
GET    /health                       所有服务均实现
```

---

## 5. 前端三视图

```
/researcher
  ├── /datasets          数据集管理（创建/上传/列表）
  ├── /annotate/:id      标注工具（canvas 画框 + 输入文字/LaTeX）
  ├── /training          提交训练任务（选数据集/配置超参数）
  └── /training/:id      训练进度实时监控（WebSocket loss/accuracy 曲线）

/student
  ├── /upload            拍照/上传图片
  ├── /recognize         识别结果（文字 + KaTeX 公式渲染）
  └── /history           历史识别记录

/operator
  ├── /dashboard         系统概览（GPU 使用率/任务队列/在线模型）
  ├── /models            模型版本管理（上线/下线/准确率对比）
  ├── /users             用户管理
  └── /logs              推理日志 + 错误追踪
```

**关键 UI 组件：**
- **标注画板**：canvas 画框 + 右键菜单（文字/公式/图表类型）
- **公式预览**：输入 LaTeX 实时渲染（KaTeX）
- **训练监控**：loss/accuracy 折线图（WebSocket 实时更新）
- **识别结果**：原图与识别文字对照，公式区域渲染为 KaTeX

---

## 6. 错误处理

| 场景 | 处理策略 |
|------|---------|
| 训练失败 | Celery 自动重试 3 次，失败后 `status=failed`，前端轮询感知 |
| 推理超时 | 30s 超时，返回 `{"error":"timeout","partial":...}` |
| GPU OOM | 捕获 CUDA OOM，自动降 batch_size 重试一次，仍失败则告知用户 |
| MinIO 上传失败 | 前端分片上传 + 断点续传，后端 MD5 校验完整性 |
| 服务不可用 | 网关层 502 统一处理，前端友好提示 |

---

## 7. 测试策略

| 层次 | 工具 | 覆盖率目标 |
|------|------|-----------|
| 单元测试 | pytest + pytest-cov | 80% |
| API 集成测试 | pytest + httpx | 核心接口 100% |
| 前端组件测试 | Vitest + React Testing Library | 70% |
| E2E 关键路径 | Playwright | 标注→训练→推理完整流 |

---

## 8. Docker Compose GPU 分配

```yaml
training-service:
  deploy:
    resources:
      reservations:
        devices:
          - driver: nvidia
            device_ids: ["0"]   # V100 #1 专供训练

inference-service:
  deploy:
    resources:
      reservations:
        devices:
          - driver: nvidia
            device_ids: ["1"]   # V100 #2 专供推理
```

---

## 9. Pipeline config.json 关键配置

```json
{
  "project_name": "paddleocr-training-system",
  "testing": {
    "coverage_tool": "pytest-cov",
    "coverage_format": ["lcov", "json"],
    "coverage_output_dir": ".pipeline/artifacts/coverage/",
    "coverage_threshold": 80
  },
  "autosteps": {
    "contract_compliance": {
      "service_start_cmd": "docker compose up -d --wait",
      "service_base_url": "http://localhost:80",
      "health_path": "/health"
    }
  }
}
```

---

## 10. 范围边界

**本期包含：**
- 7 个微服务完整实现（含 Docker Compose 编排）
- 内置标注工具（画框 + 文字/公式标签）
- PaddleOCR 训练任务管理（提交/监控/取消）
- 推理服务集成 pix2tex（公式 → LaTeX）
- React 三角色 UI

**本期不包含：**
- 自训练公式识别模型（使用 pix2tex 现成模型）
- 多机分布式训练
- 模型量化/蒸馏
- 移动端 App
