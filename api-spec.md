# DeepForge HTTP / SSE 接口规格说明

> **版本**：1.0  
> **日期**：2026-05-12  
> **依据**  
> - 前端工程：`deepforge-web`（已扫描 `src/**/*.vue`、`src/**/*.ts`：**未发现** `axios` / `fetch('/api` 等真实后端调用；数据来自 `src/mock/*` 与 Pinia，下表为 **对接约定**）。  
> - 产品/协作：《前端开发文档.md》§8（REST、SSE、鉴权、错误体）。  
> - 数据模型：`database-design.md`（表 `df_*` 与 `public_id` 约定）。  
> **维护**：新增页面或字段时，同步更新本文档与 `database-design.md`。

---

## 第一部分：接口规则（全局约定）

### 1.1 Base URL 与版本

| 环境 | Base URL（示例，部署时替换域名） |
|------|----------------------------------|
| 生产 | `https://api.deepforge.example.com/v1` |
| 联调 / 本地后端 | `http://127.0.0.1:8000/v1` |
| 前端 Vite 代理 | 开发中可将 `vite.config.ts` 配置 `server.proxy['/v1'] -> 127.0.0.1:8000`，前端请求写相对路径 **`/v1`** |

- 本文档下列路径均为 **去掉 Base 后的相对路径**，以 **`/v1`** 开头。  
- **资源主键**：对外统一使用 **`public_id`**（字符串，如 `tsk-demo-aurora`、`run_xxx`、`cp-aurora-final`），与当前前端 mock 及 `database-design.md` 一致；内部数字 `id` 仅出现在管理端或可选查询参数 `internal_id`。

### 1.2 协议与编码

- **HTTPS**（生产必选）；本地 HTTP 可接受。  
- **字符集**：UTF-8；请求/响应 `Content-Type: application/json`（文件上传除外）。  
- **时间**：ISO 8601，UTC，带毫秒建议 `2026-05-12T09:41:00.000Z`（与 DB `DATETIME(3)` UTC 一致）。

### 1.3 鉴权

| 项 | 约定 |
|----|------|
| 方式 | `Authorization: Bearer <access_token>` |
| 刷新 | `POST /v1/auth/refresh` Body `{ "refresh_token": "..." }`（可选实现） |
| SSE | 浏览器 `EventSource` 无法自定义 Header 时，允许 **`?access_token=`** 或 **Cookie** 会话（二选一由部署约定，须在网关校验） |
| 匿名 | 仅开发环境可开放；生产所有业务接口需鉴权 |

### 1.4 统一错误体（与《前端开发文档》一致）

HTTP 状态码非 2xx 时，响应体 JSON：

```json
{
  "code": "TASK_NOT_FOUND",
  "message": "任务不存在或已删除",
  "details": {}
}
```

- `code`：机器可读枚举字符串。  
- `message`：给人看的说明（可 i18n）。  
- `details`：可选，校验错误时放字段级信息。

### 1.5 分页与列表（工作台等）

查询参数约定：

| 参数 | 类型 | 说明 |
|------|------|------|
| `page` | int | 从 1 开始，默认 1 |
| `page_size` | int | 默认 20，最大 100 |
| `q` | string | 搜索关键词（标题、摘要、public_id） |
| `sort` | string | 如 `updated_at:desc`，默认 `updated_at:desc` |

列表响应包装：

```json
{
  "items": [],
  "total": 0,
  "page": 1,
  "page_size": 20
}
```

### 1.6 幂等与重试

- `POST` 创建类：客户端可带 **`Idempotency-Key: <uuid>`** 头，服务端 24h 内相同 Key 返回同一资源，避免重复建任务。  
- SSE 断线重连：使用 **`Last-Event-ID`** 头（若服务端支持）或 Query `since_seq=123` 从 `df_stream_event.seq` 之后续传。

### 1.7 SSE 事件通道（全局）

- **路径模板**：`GET /v1/tasks/{task_public_id}/runs/{run_public_id}/stream`  
- **Content-Type**：`text/event-stream`  
- **事件名**：与文档一致，如 `agent.message`、`graph.update`、`metrics.tick`、`phase.change`、`conclusion.ready`、`report.ready`、`world.checkpoint`、`error`  
- **负载**：每行 `data: <JSON>\n\n`，JSON 内含 `seq`、`timestamp`、`payload` 等（与 `df_stream_event` 对齐）

---

## 第二部分：页面扫描 → 应对接接口

说明：**「当前实现」** 指 `deepforge-web` 现状；**「应对接真实地址」** 为后端 Python（如 FastAPI）应实现的 **完整 URL 路径**（前缀为 Base + `/v1`）。

| 路由（前端） | Vue 文件 | 当前实现 | 应对接接口摘要 | HTTP | 真实路径（相对 `/v1`） |
|--------------|----------|----------|------------------|------|-------------------------|
| `/` | `views/HomeView.vue` | `useTaskStore.list` + 本地 `MOCK_TASKS` | 任务分页列表、搜索 `q` | GET | `/tasks` |
| `/tasks/new` | `views/TaskNewView.vue` | `taskStore.createDraft` 仅本地 | 创建任务 + 初始输入 | POST | `/tasks` |
| `/tasks/:id` | `views/TaskDetailView.vue` | mock：`MOCK_*` 按 id 取 | 任务详情聚合 | GET | `/tasks/{task_public_id}` |
| 同上·沙盒 Tab | 同上 | `MOCK_AGENTS[id]` | 沙盒 Agent 列表 | GET | `/tasks/{task_public_id}/agents` |
| 同上·结论与报告 | 同上 | `MOCK_CONCLUSIONS`、`MOCK_REPORTS` | 结论列表、报告列表/最新 | GET | `/tasks/{task_public_id}/conclusions`、`/tasks/{task_public_id}/reports` |
| 同上·图谱 Tab | 同上 + `G6GraphView.vue` | `MOCK_GRAPH` 写死 | 最新或指定快照下图谱 | GET | `/tasks/{task_public_id}/graph` |
| 同上·对比 Tab | 同上 | `MOCK_COMPARE` | A/B 对比配置 | GET | `/tasks/{task_public_id}/ab-compare` |
| `/tasks/:id/live` | `views/TaskLiveView.vue` | `MOCK_PIPELINE` + `liveLogStore` 定时器 | 运行阶段列表 + SSE | GET + GET(SSE) | `/tasks/{task_public_id}/runs/{run_public_id}/stages`、`/tasks/.../runs/.../stream` |
| `/tasks/:id/world` | `views/TaskWorldView.vue` | `MOCK_CHECKPOINTS` | 快照列表、续跑、分叉 | GET + POST | `/tasks/{task_public_id}/checkpoints`、见下文 §3.6 |
| `/settings` | `views/SettingsView.vue` | 表单禁用无请求 | 当前用户偏好 | GET / PATCH | `/users/me/preferences` |
| 顶栏搜索 | `components/layout/AppHeader.vue` | `router.push({ query: { q }})` 仅前端 | 同工作台列表 `q` | GET | `/tasks?q=...` |
| `PipelineCard.vue` | 组件 | 展示 `step.apiPath` 为 **文案 mock**（如 `POST /api/mock/...`） | 对应真实后端见 §3.7 映射表 | — | — |

---

## 第三部分：REST 接口清单（真实路径与 DB 映射）

以下路径均相对于 **`{BASE}/v1`**。示例完整 URL：  
`https://api.deepforge.example.com/v1/tasks/tsk-demo-aurora`

### 3.1 认证与用户

| 方法 | 路径 | 说明 | 主要数据表 |
|------|------|------|------------|
| POST | `/auth/login` | 登录，Body：`email`, `password` → 返回 `access_token`, `refresh_token` | `df_user` |
| POST | `/auth/refresh` | 刷新访问令牌 | — |
| GET | `/users/me` | 当前用户基本信息 | `df_user` |
| PATCH | `/users/me` | 修改展示名等 | `df_user` |
| GET | `/users/me/preferences` | 默认模型、主题等 | `df_user_preference` |
| PATCH | `/users/me/preferences` | 更新偏好；敏感字段如 API Key 加密存储 | `df_user_preference` |

### 3.2 任务（工作台 / 新建 / 详情概览）

| 方法 | 路径 | 说明 | 主要数据表 |
|------|------|------|------------|
| GET | `/tasks` | 分页列表，Query：`page`, `page_size`, `q`, `phase`, `mode` | `df_task` |
| POST | `/tasks` | 创建任务；Body 示例见 §4 | `df_task`, `df_task_input` |
| GET | `/tasks/{task_public_id}` | 详情（可含嵌套 summary：最近 run、阶段概要，由后端聚合） | `df_task` 及关联 |
| PATCH | `/tasks/{task_public_id}` | 更新标题、阶段（受状态机约束）等 | `df_task` |
| DELETE | `/tasks/{task_public_id}` | 软删除 | `df_task.deleted_at` |

### 3.3 任务输入与附件（新建推演步骤）

| 方法 | 路径 | 说明 | 主要数据表 |
|------|------|------|------------|
| GET | `/tasks/{task_public_id}/input` | 规则文本、λ、扩展 JSON | `df_task_input` |
| PUT | `/tasks/{task_public_id}/input` | 全量更新输入 | `df_task_input` |
| POST | `/tasks/{task_public_id}/attachments` | `multipart/form-data` 上传背景资料 | `df_task_attachment` |
| GET | `/tasks/{task_public_id}/attachments` | 附件列表 | `df_task_attachment` |
| DELETE | `/tasks/{task_public_id}/attachments/{attachment_public_id}` | 删除附件 | `df_task_attachment` |

### 3.4 沙盒与推演运行

| 方法 | 路径 | 说明 | 主要数据表 |
|------|------|------|------------|
| POST | `/tasks/{task_public_id}/sandbox/spawn` | 生成沙盒与 Agent（异步可返回 `job_id`） | `df_sandbox_agent`、任务阶段更新 |
| GET | `/tasks/{task_public_id}/agents` | 沙盒 Agent 列表 | `df_sandbox_agent` |
| POST | `/tasks/{task_public_id}/runs` | 开启一次推演；Body 可选 `checkpoint_public_id` 表示从快照续跑 | `df_simulation_run`, `df_world_checkpoint` |
| GET | `/tasks/{task_public_id}/runs` | 运行历史列表 | `df_simulation_run` |
| GET | `/tasks/{task_public_id}/runs/{run_public_id}` | 单次运行详情 | `df_simulation_run` |
| POST | `/tasks/{task_public_id}/runs/{run_public_id}/pause` | 暂停 | run.status |
| POST | `/tasks/{task_public_id}/runs/{run_public_id}/resume` | 恢复 | run.status |
| POST | `/tasks/{task_public_id}/runs/{run_public_id}/cancel` | 取消 | run.status |

### 3.5 推演实况：阶段流水线 + SSE

| 方法 | 路径 | 说明 | 主要数据表 |
|------|------|------|------------|
| GET | `/tasks/{task_public_id}/runs/{run_public_id}/stages` | 右侧流水线卡片数据（顺序、状态、api 文案、tags、metrics） | `df_run_stage`, `df_run_stage_tag` |
| GET | `/tasks/{task_public_id}/runs/{run_public_id}/stream` | **SSE** 事件流（见 §1.7） | `df_stream_event`（可选落库） |
| POST | `/tasks/{task_public_id}/runs/{run_public_id}/interventions` | 中途干预；Body：`instruction_text`, `simulation_time_anchor` | `df_intervention` |

### 3.6 世界快照（世界快照页）

| 方法 | 路径 | 说明 | 主要数据表 |
|------|------|------|------------|
| GET | `/tasks/{task_public_id}/checkpoints` | 快照列表 | `df_world_checkpoint` |
| GET | `/tasks/{task_public_id}/checkpoints/{checkpoint_public_id}` | 快照详情（含 `world_state_uri` 元数据，大对象不直出） | `df_world_checkpoint` |
| POST | `/tasks/{task_public_id}/checkpoints/{checkpoint_public_id}/continue` | 从该快照发起新 run；Body 可选覆盖变量 | 新 `df_simulation_run` |
| POST | `/tasks/{task_public_id}/checkpoints/{checkpoint_public_id}/fork` | 分叉为新任务 | 新 `df_task` + 关联源 checkpoint |

### 3.7 结论、报告、图谱、A/B

| 方法 | 路径 | 说明 | 主要数据表 |
|------|------|------|------------|
| GET | `/tasks/{task_public_id}/conclusions` | Query：`run_public_id` 可选 | `df_conclusion` |
| GET | `/tasks/{task_public_id}/reports` | 报告版本列表 | `df_report` |
| GET | `/tasks/{task_public_id}/reports/latest` | 最新一条（便于前端） | `df_report` |
| POST | `/tasks/{task_public_id}/reports/generate` | 触发生成 PDF/Markdown；Body 可选 `run_public_id` | 异步 + `df_report` |
| GET | `/tasks/{task_public_id}/reports/{report_public_id}/pdf` | 302 到对象存储或流式下载 | `df_report.pdf_storage_uri` |
| GET | `/tasks/{task_public_id}/graph` | Query：`run_public_id`, `checkpoint_public_id`, `snapshot_public_id` 三选一或默认最新 | `df_graph_snapshot`, `df_graph_node`, `df_graph_edge` |
| GET | `/tasks/{task_public_id}/ab-compare` | A/B 文案 | `df_ab_compare` |

### 3.8 Mock 卡片中的 `apiPath` → 真实路径映射（PipelineCard 文案对齐）

前端 `MOCK_PIPELINE` 中仅为展示字符串，后端实现时建议统一为下表：

| Mock 展示（示例） | 真实方法 + 路径 |
|-------------------|-----------------|
| `POST /api/mock/rules/inject` | `PUT /v1/tasks/{task_public_id}/input`（规则写入输入表） |
| `POST /api/mock/world/bible` | `PUT /v1/tasks/{task_public_id}/input` 或专用 `POST /v1/tasks/{task_public_id}/world-bible`（若单独表再扩展） |
| `POST /api/mock/sandbox/spawn` | `POST /v1/tasks/{task_public_id}/sandbox/spawn` |
| `GET /api/mock/tasks/{id}/stream` | `GET /v1/tasks/{task_public_id}/runs/{run_public_id}/stream` |
| `POST /api/mock/conclusions/finalize` | 由运行结束任务自动写入；或 `POST /v1/tasks/.../runs/.../conclusions/finalize`（管理用） |
| `POST /api/mock/reports/render` | `POST /v1/tasks/{task_public_id}/reports/generate` |
| `GET /api/mock/world/checkpoints` | `GET /v1/tasks/{task_public_id}/checkpoints` |

---

## 第四部分：请求/响应 DTO 示例

### 4.1 `POST /v1/tasks` 创建任务

**Request**

```json
{
  "title": "演示任务 · 未命名沙盒",
  "mode": "舆情",
  "input": {
    "rules_text": "规则摘要……",
    "lambda_demo": 42,
    "variables_json": {}
  }
}
```

**Response** `201`

```json
{
  "task": {
    "public_id": "tsk-demo-9001",
    "title": "演示任务 · 未命名沙盒",
    "mode": "舆情",
    "phase": "sandbox_ready",
    "summary": null,
    "updated_at": "2026-05-12T08:00:00.000Z"
  }
}
```

### 4.2 `GET /v1/tasks/{task_public_id}` 详情（聚合示例）

```json
{
  "task": { "public_id": "tsk-demo-aurora", "title": "…", "mode": "舆情", "phase": "completed", "summary": "…", "updated_at": "…" },
  "latest_run": { "public_id": "run_xxx", "status": "completed" },
  "counts": { "checkpoints": 2, "agents": 3 }
}
```

（亦可拆为多请求，由前端并行拉取以降低单次负载。）

### 4.3 SSE `data` 帧 JSON 示例

```json
{
  "seq": 1001,
  "event_type": "agent.message",
  "timestamp": "2026-05-12T08:10:00.000Z",
  "payload": {
    "agent_public_id": "ag-01",
    "content": "……"
  }
}
```

---

## 第五部分：与 `database-design.md` 的对应关系

| 接口资源 | 核心表 |
|----------|--------|
| `/users/me*` | `df_user`, `df_user_preference` |
| `/tasks` | `df_task` |
| `/tasks/.../input` | `df_task_input` |
| `/tasks/.../attachments` | `df_task_attachment` |
| `/tasks/.../runs` | `df_simulation_run` |
| `/tasks/.../agents` | `df_sandbox_agent` |
| `/tasks/.../checkpoints` | `df_world_checkpoint` |
| `/tasks/.../conclusions` | `df_conclusion` |
| `/tasks/.../reports` | `df_report` |
| `/tasks/.../runs/.../stages` | `df_run_stage`, `df_run_stage_tag` |
| `/tasks/.../runs/.../stream`（事件） | `df_stream_event`（可选） |
| `/tasks/.../runs/.../interventions` | `df_intervention` |
| `/tasks/.../graph` | `df_graph_snapshot`, `df_graph_node`, `df_graph_edge` |
| `/tasks/.../ab-compare` | `df_ab_compare` |

---

## 第六部分：OpenAPI 与前端后续对接建议

1. 后端使用 **FastAPI** 时，建议生成 **OpenAPI 3** JSON：`/v1/openapi.json`，前端用 **orval / openapi-typescript** 生成 `src/api` 客户端，替换当前 `mock/`。  
2. 前端 `vite` 配置 `proxy`：`/v1` → 本地 FastAPI，环境变量 `VITE_API_BASE=/v1`。  
3. **替换 Pinia**：`taskStore` 的 `list/getById/createDraft` 改为调用 `GET/POST /v1/tasks`；各 View 在 `onMounted` 拉取对应子资源。

---

## 修订记录

| 版本 | 日期 | 说明 |
|------|------|------|
| 1.0 | 2026-05-12 | 初版：扫描 `deepforge-web` 全页面；无真实调用处已标注；全量 REST/SSE 与 `database-design.md` 对齐 |

---

**维护约定**：新增 Vue 页面或后端路由时，在 **「第二部分」** 增加一行映射，在 **「第三部分」** 增加或修改路径表，并更新修订记录；数据库变更以 `database-design.md` 为准同步本文件「第五部分」。
