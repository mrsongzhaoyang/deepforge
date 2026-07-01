# DeepForge 数据库设计说明

> **版本**：1.0  
> **依据**：《前端开发文档.md》V1.1（推演产出物、SSE、任务阶段、沙盒/图谱/对比等）与 `deepforge-web` 中 `src/mock/types.ts`、`src/mock/tasks.ts` 及 Pinia 本地创建任务逻辑。  
> **用途**：后端（如 FastAPI + MySQL/PostgreSQL）建表、迁移与接口 DTO 对齐；**新增表或字段时请在本文件同步追加并升高版本号**。  
> **字符集建议**：`utf8mb4`，排序规则 `utf8mb4_unicode_ci`（MySQL）或等价（PostgreSQL）。

---

## 1. 设计原则

| 原则 | 说明 |
|------|------|
| 主键 | 推荐使用 **BIGINT 自增** `id` 作为内部主键；对外/API 可使用 **`public_id`（VARCHAR，如 `tsk_xxx`）** 与前端当前 mock 风格兼容。 |
| 多租户 | 预留 `org_id`（组织），个人演示可为 NULL 或默认组织。 |
| 软删除 | 业务表统一 `deleted_at`（可空时间），查询默认 `WHERE deleted_at IS NULL`。 |
| 审计 | `created_at`、`updated_at`；必要时 `created_by`、`updated_by` 关联 `df_user.id`。 |
| JSON | 动态变量、图谱整包、流水线 metrics 等用 **JSON**（MySQL `JSON` / PG `jsonb`），在注释中标明结构约定。 |
| 时区 | 一律 **UTC** 存库；`TIMESTAMP` 或带时区的 `timestamptz`；展示由前端按用户时区转换。 |

---

## 2. 枚举与字典（与前端类型对齐）

### 2.1 推演模式 `sim_mode`（对应 `SimMode`）

> **实现二选一**：(A) 下表 **规范化英文枚举** 存 `df_task.mode`，接口层与前端互转；(B) 直接存与 mock 一致的中文：`舆情`、`企业`、`创作`、`法律市监`、`组织行为`，便于初期与前端 mock 对齐。

| 值（规范化） | 说明（中文） |
|----|------|
| `PUBLIC_OPINION` | 舆情 |
| `ENTERPRISE` | 企业 |
| `CREATION` | 创作 |
| `LEGAL_MARKET` | 法律市监 |
| `ORG_BEHAVIOR` | 组织行为 |

### 2.2 任务阶段 `task_phase`（对应 `TaskPhase`）

| 值 | 说明 |
|----|------|
| `draft` | 草稿 |
| `sandbox_ready` | 沙盒就绪 |
| `running` | 推演中 |
| `paused` | 已暂停 |
| `completed` | 已完成 |

### 2.3 智能体立场 `agent_stance`

| 值 | 说明 |
|----|------|
| `support` | 支持 |
| `hesitate` | 犹豫 |
| `oppose` | 反对 |
| `neutral` | 中立 |

### 2.4 结论级别 `conclusion_level`（对应 `MockConclusion.level`）

| 值 | 说明 |
|----|------|
| `info` | 信息类结论 |
| `risk` | 风险类 |
| `action` | 可执行建议类 |

### 2.5 报告 PDF 状态 `report_pdf_status`（对应 `MockReportMeta.pdfStatus`）

| 值 | 说明 |
|----|------|
| `idle` | 未生成 |
| `queued` | 排队中 |
| `generating` | 生成中 |
| `ready` | 可下载 |
| `failed` | 失败 |

### 2.6 流水线步骤状态 `pipeline_step_status`（对应 `MockPipelineStep.status`）

| 值 | 说明 |
|----|------|
| `pending` | 待开始 |
| `running` | 进行中 |
| `done` | 完成 |
| `error` | 异常 |

### 2.7 SSE 事件类型（文档 §8，持久化可选）

`agent.message`、`graph.update`、`metrics.tick`、`phase.change`、`conclusion.ready`、`report.ready`、`world.checkpoint`、`error` 等存入 `df_stream_event.event_type`（VARCHAR）。

---

## 3. ER 关系概要（文字）

- **组织** `df_organization` 1 — N **用户成员** `df_org_member` — N **用户** `df_user`。  
- **用户** N — 1 **组织**（主归属）；**任务** `df_task` 归属组织与用户。  
- **任务** 1 — 1 **任务输入** `df_task_input`（规则、变量 λ、扩展 JSON）；1 — N **附件** `df_task_attachment`。  
- **任务** 1 — N **推演运行** `df_simulation_run`（一次「从开启到结束」）；运行 1 — N **阶段步骤** `df_run_stage`（对齐流水线卡片）；运行 1 — N **流事件** `df_stream_event`；运行 1 — N **干预** `df_intervention`。  
- **任务** 1 — N **沙盒智能体** `df_sandbox_agent`（当前沙盒视图；若需历史版本可改挂 `run_id`）。  
- **运行** 1 — N **世界快照** `df_world_checkpoint`（可续推演）；快照可关联 **图谱快照** `df_graph_snapshot`。  
- **任务/运行** 1 — N **结论** `df_conclusion`；**任务/运行** 1 — N **报告** `df_report`（多版本）。  
- **任务** 0 — 1 **A/B 对比配置** `df_ab_compare`（演示用结构化文案；复杂对比可升级为两 `run_id`）。  

---

## 4. 表结构定义（字段均含中文说明）

以下为 **MySQL 8.0** 风格 DDL；若使用 PostgreSQL，将 `BIGINT UNSIGNED` 改为 `BIGSERIAL`、`JSON` 改为 `jsonb`、`DATETIME(3)` 改为 `timestamptz` 等即可。

### 4.1 `df_user` — 用户

| 字段名 | 类型 | 空 | 默认值 | 中文说明 |
|--------|------|----|--------|----------|
| `id` | BIGINT UNSIGNED | NO | 自增 | 内部主键 |
| `public_id` | VARCHAR(32) | NO | — | 对外用户编号（UUID 短码等） |
| `org_id` | BIGINT UNSIGNED | YES | NULL | 默认所属组织 ID |
| `display_name` | VARCHAR(128) | NO | — | 展示名称（如「演示用户」） |
| `email` | VARCHAR(255) | YES | NULL | 登录邮箱 |
| `password_hash` | VARCHAR(255) | YES | NULL | 密码哈希；OAuth 可空 |
| `avatar_url` | VARCHAR(512) | YES | NULL | 头像地址 |
| `status` | TINYINT | NO | 1 | 状态：1 正常 0 禁用 |
| `created_at` | DATETIME(3) | NO | CURRENT_TIMESTAMP(3) | 创建时间 |
| `updated_at` | DATETIME(3) | NO | CURRENT_TIMESTAMP(3) ON UPDATE | 更新时间 |
| `deleted_at` | DATETIME(3) | YES | NULL | 软删除时间 |

**索引**：`UNIQUE(public_id)`，`INDEX(org_id)`，`UNIQUE(email)`（若邮箱非空唯一策略按产品定）。

---

### 4.2 `df_organization` — 组织（多租户）

| 字段名 | 类型 | 空 | 默认值 | 中文说明 |
|--------|------|----|--------|----------|
| `id` | BIGINT UNSIGNED | NO | 自增 | 内部主键 |
| `public_id` | VARCHAR(32) | NO | — | 对外组织编号 |
| `name` | VARCHAR(256) | NO | — | 组织名称（演示：虚构组织 · 星云实验室） |
| `created_at` | DATETIME(3) | NO | CURRENT_TIMESTAMP(3) | 创建时间 |
| `updated_at` | DATETIME(3) | NO | CURRENT_TIMESTAMP(3) ON UPDATE | 更新时间 |
| `deleted_at` | DATETIME(3) | YES | NULL | 软删除时间 |

---

### 4.3 `df_org_member` — 组织成员关系

| 字段名 | 类型 | 空 | 默认值 | 中文说明 |
|--------|------|----|--------|----------|
| `id` | BIGINT UNSIGNED | NO | 自增 | 内部主键 |
| `org_id` | BIGINT UNSIGNED | NO | — | 组织 ID |
| `user_id` | BIGINT UNSIGNED | NO | — | 用户 ID |
| `role` | VARCHAR(32) | NO | `member` | 角色：owner/admin/member 等 |
| `created_at` | DATETIME(3) | NO | CURRENT_TIMESTAMP(3) | 加入时间 |

**索引**：`UNIQUE(org_id, user_id)`。

---

### 4.4 `df_user_preference` — 用户偏好与模型设置（对齐设置页）

| 字段名 | 类型 | 空 | 默认值 | 中文说明 |
|--------|------|----|--------|----------|
| `id` | BIGINT UNSIGNED | NO | 自增 | 内部主键 |
| `user_id` | BIGINT UNSIGNED | NO | — | 用户 ID，唯一 |
| `default_llm_model` | VARCHAR(128) | YES | NULL | 默认大模型标识（演示 mock-llm-v0） |
| `api_key_cipher` | VARBINARY(4096) | YES | NULL | API Key 密文存储；仅存密文不建议明文 |
| `theme` | VARCHAR(16) | YES | `dark` | 主题：dark/light |
| `extra_json` | JSON | YES | NULL | 其它 JSON 配置 |
| `updated_at` | DATETIME(3) | NO | CURRENT_TIMESTAMP(3) ON UPDATE | 更新时间 |

**索引**：`UNIQUE(user_id)`。

---

### 4.5 `df_task` — 推演任务（对齐 `MockTask` + `createDraft`）

| 字段名 | 类型 | 空 | 默认值 | 中文说明 |
|--------|------|----|--------|----------|
| `id` | BIGINT UNSIGNED | NO | 自增 | 内部主键 |
| `public_id` | VARCHAR(64) | NO | — | 对外任务 ID（如 `tsk-demo-aurora` / `tsk-demo-9001`） |
| `org_id` | BIGINT UNSIGNED | YES | NULL | 所属组织 |
| `owner_user_id` | BIGINT UNSIGNED | NO | — | 任务负责人用户 ID |
| `title` | VARCHAR(512) | NO | — | 任务标题 |
| `mode` | VARCHAR(32) | NO | — | 推演模式，见 §2.1 枚举存储值 |
| `phase` | VARCHAR(32) | NO | `draft` | 当前阶段，见 §2.2 |
| `summary` | VARCHAR(1024) | YES | NULL | 列表/概览摘要（对齐 mock `summary`） |
| `created_at` | DATETIME(3) | NO | CURRENT_TIMESTAMP(3) | 创建时间 |
| `updated_at` | DATETIME(3) | NO | CURRENT_TIMESTAMP(3) ON UPDATE | 最近更新时间（工作台排序） |
| `deleted_at` | DATETIME(3) | YES | NULL | 软删除时间 |

**索引**：`UNIQUE(public_id)`，`INDEX(owner_user_id, updated_at)`，`INDEX(org_id, phase)`。

---

### 4.6 `df_task_input` — 任务创建时的规则与变量（对齐 `TaskNewView`）

| 字段名 | 类型 | 空 | 默认值 | 中文说明 |
|--------|------|----|--------|----------|
| `id` | BIGINT UNSIGNED | NO | 自增 | 内部主键 |
| `task_id` | BIGINT UNSIGNED | NO | — | 任务 ID，一对一 |
| `rules_text` | MEDIUMTEXT | YES | NULL | 规则/背景摘要正文（演示规则注入） |
| `lambda_demo` | INT | YES | NULL | 演示变量 λ（0–100，仅演示含义时可为 NULL） |
| `variables_json` | JSON | YES | NULL | 扩展变量键值（未来动态表单） |
| `created_at` | DATETIME(3) | NO | CURRENT_TIMESTAMP(3) | 创建时间 |
| `updated_at` | DATETIME(3) | NO | CURRENT_TIMESTAMP(3) ON UPDATE | 更新时间 |

**索引**：`UNIQUE(task_id)`。

---

### 4.7 `df_task_attachment` — 任务背景资料附件

| 字段名 | 类型 | 空 | 默认值 | 中文说明 |
|--------|------|----|--------|----------|
| `id` | BIGINT UNSIGNED | NO | 自增 | 内部主键 |
| `task_id` | BIGINT UNSIGNED | NO | — | 任务 ID |
| `file_name` | VARCHAR(512) | NO | — | 原始文件名 |
| `storage_path` | VARCHAR(1024) | NO | — | 对象存储或本地路径 |
| `mime_type` | VARCHAR(128) | YES | NULL | MIME 类型 |
| `size_bytes` | BIGINT UNSIGNED | YES | NULL | 文件大小（字节） |
| `created_at` | DATETIME(3) | NO | CURRENT_TIMESTAMP(3) | 上传时间 |

**索引**：`INDEX(task_id)`。

---

### 4.8 `df_simulation_run` — 单次推演运行（承接 checkpoint / 报告 / 结论归属）

| 字段名 | 类型 | 空 | 默认值 | 中文说明 |
|--------|------|----|--------|----------|
| `id` | BIGINT UNSIGNED | NO | 自增 | 内部主键 |
| `public_id` | VARCHAR(64) | NO | — | 对外运行编号 |
| `task_id` | BIGINT UNSIGNED | NO | — | 所属任务 |
| `status` | VARCHAR(32) | NO | `pending` | 运行状态：pending/running/completed/failed/cancelled |
| `started_at` | DATETIME(3) | YES | NULL | 开始推演时间 |
| `ended_at` | DATETIME(3) | YES | NULL | 结束时间 |
| `parent_checkpoint_id` | BIGINT UNSIGNED | YES | NULL | 若从某快照续跑，指向 `df_world_checkpoint.id` |
| `forked_from_task_id` | BIGINT UNSIGNED | YES | NULL | 若分叉为新任务，记录源任务（可选） |
| `created_at` | DATETIME(3) | NO | CURRENT_TIMESTAMP(3) | 创建时间 |

**索引**：`UNIQUE(public_id)`，`INDEX(task_id, started_at)`。

---

### 4.9 `df_sandbox_agent` — 沙盒智能体（对齐 `MockAgent`，按任务维度）

| 字段名 | 类型 | 空 | 默认值 | 中文说明 |
|--------|------|----|--------|----------|
| `id` | BIGINT UNSIGNED | NO | 自增 | 内部主键 |
| `public_id` | VARCHAR(64) | NO | — | 对外 Agent 标识（如 `ag-01`） |
| `task_id` | BIGINT UNSIGNED | NO | — | 所属任务 |
| `run_id` | BIGINT UNSIGNED | YES | NULL | 可选：绑定到某次运行快照；NULL 表示当前沙盒 |
| `name` | VARCHAR(256) | NO | — | 显示名称 |
| `role` | VARCHAR(128) | NO | — | 角色类型（意见领袖/财务等） |
| `stance` | VARCHAR(32) | NO | — | 立场，见 §2.3 |
| `weight_note` | VARCHAR(512) | YES | NULL | 权重说明（如 1:9:90、现金流敏感） |
| `sort_order` | INT | NO | 0 | 列表排序 |
| `created_at` | DATETIME(3) | NO | CURRENT_TIMESTAMP(3) | 创建时间 |

**索引**：`INDEX(task_id)`，`INDEX(task_id, run_id)`。

---

### 4.10 `df_world_checkpoint` — 世界快照 / 可续推演（对齐 `MockCheckpoint`）

| 字段名 | 类型 | 空 | 默认值 | 中文说明 |
|--------|------|----|--------|----------|
| `id` | BIGINT UNSIGNED | NO | 自增 | 内部主键 |
| `public_id` | VARCHAR(64) | NO | — | 对外快照 ID（如 `cp-aurora-final`） |
| `task_id` | BIGINT UNSIGNED | NO | — | 所属任务 |
| `run_id` | BIGINT UNSIGNED | YES | NULL | 所属推演运行；NULL 时可仅挂任务 |
| `label` | VARCHAR(256) | NO | — | 快照标题（如 T+48h 虚构峰值） |
| `summary` | VARCHAR(1024) | YES | NULL | 快照摘要 |
| `world_state_uri` | VARCHAR(1024) | YES | NULL | 完整世界状态对象存储 URI（大对象） |
| `world_state_json` | JSON | YES | NULL | 或可内联小状态；与 URI 二选一或并存 |
| `simulation_time_label` | VARCHAR(128) | YES | NULL | 推演内时间标签（如 T+48h） |
| `created_at` | DATETIME(3) | NO | CURRENT_TIMESTAMP(3) | 快照生成时间（对齐 mock `createdAt`） |

**索引**：`UNIQUE(public_id)`，`INDEX(task_id, created_at)`，`INDEX(run_id)`。

---

### 4.11 `df_conclusion` — 推演结论（对齐 `MockConclusion`）

| 字段名 | 类型 | 空 | 默认值 | 中文说明 |
|--------|------|----|--------|----------|
| `id` | BIGINT UNSIGNED | NO | 自增 | 内部主键 |
| `public_id` | VARCHAR(64) | NO | — | 对外结论条 ID（演示 c1/c2） |
| `task_id` | BIGINT UNSIGNED | NO | — | 所属任务 |
| `run_id` | BIGINT UNSIGNED | YES | NULL | 所属运行；多轮推演时区分 |
| `checkpoint_id` | BIGINT UNSIGNED | YES | NULL | 可选：关联产生该结论的快照 |
| `level` | VARCHAR(16) | NO | — | 结论级别，见 §2.4 |
| `content` | TEXT | NO | — | 结论文本 |
| `sort_order` | INT | NO | 0 | 展示顺序 |
| `created_at` | DATETIME(3) | NO | CURRENT_TIMESTAMP(3) | 创建时间 |

**索引**：`INDEX(task_id)`，`INDEX(run_id)`。

---

### 4.12 `df_report` — 预测报告版本（对齐 `MockReportMeta` + 正文扩展）

| 字段名 | 类型 | 空 | 默认值 | 中文说明 |
|--------|------|----|--------|----------|
| `id` | BIGINT UNSIGNED | NO | 自增 | 内部主键 |
| `task_id` | BIGINT UNSIGNED | NO | — | 所属任务 |
| `run_id` | BIGINT UNSIGNED | YES | NULL | 所属运行 |
| `version_label` | VARCHAR(128) | NO | — | 版本号展示（如 rpt-mock-20260510-01） |
| `pdf_status` | VARCHAR(32) | NO | `idle` | PDF 生成状态，见 §2.5 |
| `excerpt` | VARCHAR(2048) | YES | NULL | 摘要/摘录（列表与预览） |
| `body_markdown` | MEDIUMTEXT | YES | NULL | 报告正文 Markdown/HTML |
| `pdf_storage_uri` | VARCHAR(1024) | YES | NULL | PDF 文件存储地址 |
| `error_message` | VARCHAR(1024) | YES | NULL | 生成失败时的错误信息 |
| `created_at` | DATETIME(3) | NO | CURRENT_TIMESTAMP(3) | 该版本创建时间 |

**索引**：`INDEX(task_id, created_at)`，`INDEX(run_id)`。

---

### 4.13 `df_run_stage` — 推演流水线阶段（对齐 `MockPipelineStep`）

| 字段名 | 类型 | 空 | 默认值 | 中文说明 |
|--------|------|----|--------|----------|
| `id` | BIGINT UNSIGNED | NO | 自增 | 内部主键 |
| `run_id` | BIGINT UNSIGNED | NO | — | 所属推演运行 |
| `step_order` | INT | NO | — | 步骤序号 01/02…（对应 `order`） |
| `title` | VARCHAR(256) | NO | — | 步骤标题 |
| `status` | VARCHAR(16) | NO | — | 步骤状态，见 §2.6 |
| `api_path` | VARCHAR(512) | YES | NULL | 关联 API 路径（展示用） |
| `description` | VARCHAR(1024) | YES | NULL | 步骤说明 |
| `metrics_json` | JSON | YES | NULL | 底部指标（如 agents/edges/seeds） |
| `updated_at` | DATETIME(3) | NO | CURRENT_TIMESTAMP(3) ON UPDATE | 状态更新时间 |

**索引**：`UNIQUE(run_id, step_order)`。

---

### 4.14 `df_run_stage_tag` — 阶段标签（对齐 `MockPipelineStep.tags` 多值）

| 字段名 | 类型 | 空 | 默认值 | 中文说明 |
|--------|------|----|--------|----------|
| `id` | BIGINT UNSIGNED | NO | 自增 | 内部主键 |
| `run_stage_id` | BIGINT UNSIGNED | NO | — | 阶段 ID |
| `tag` | VARCHAR(128) | NO | — | 标签文案 |

**索引**：`INDEX(run_stage_id)`。

---

### 4.15 `df_stream_event` — SSE / 流式事件持久化（可选，用于回放与审计）

| 字段名 | 类型 | 空 | 默认值 | 中文说明 |
|--------|------|----|--------|----------|
| `id` | BIGINT UNSIGNED | NO | 自增 | 内部主键 |
| `task_id` | BIGINT UNSIGNED | NO | — | 任务 ID |
| `run_id` | BIGINT UNSIGNED | YES | NULL | 运行 ID |
| `event_type` | VARCHAR(64) | NO | — | 事件类型，见文档 §8 |
| `payload_json` | JSON | YES | NULL | 事件负载 |
| `seq` | BIGINT UNSIGNED | NO | — | 同 run 内单调序号，便于重放 |
| `created_at` | DATETIME(3) | NO | CURRENT_TIMESTAMP(3) | 事件时间 |

**索引**：`INDEX(task_id, run_id, seq)`。

---

### 4.16 `df_intervention` — 中途干预指令

| 字段名 | 类型 | 空 | 默认值 | 中文说明 |
|--------|------|----|--------|----------|
| `id` | BIGINT UNSIGNED | NO | 自增 | 内部主键 |
| `task_id` | BIGINT UNSIGNED | NO | — | 任务 ID |
| `run_id` | BIGINT UNSIGNED | NO | — | 运行 ID |
| `instruction_text` | TEXT | NO | — | 用户输入的干预内容 |
| `simulation_time_anchor` | VARCHAR(128) | YES | NULL | 推演内时刻锚点（如 T+12h） |
| `status` | VARCHAR(32) | NO | `applied` | 已应用/已排队/失败等 |
| `created_at` | DATETIME(3) | NO | CURRENT_TIMESTAMP(3) | 提交时间 |

**索引**：`INDEX(run_id, created_at)`。

---

### 4.17 `df_graph_snapshot` — 图谱快照头

| 字段名 | 类型 | 空 | 默认值 | 中文说明 |
|--------|------|----|--------|----------|
| `id` | BIGINT UNSIGNED | NO | 自增 | 内部主键 |
| `task_id` | BIGINT UNSIGNED | NO | — | 任务 ID |
| `run_id` | BIGINT UNSIGNED | YES | NULL | 运行 ID |
| `checkpoint_id` | BIGINT UNSIGNED | YES | NULL | 可选关联快照 |
| `layout_json` | JSON | YES | NULL | 布局元数据（缩放、算法等） |
| `created_at` | DATETIME(3) | NO | CURRENT_TIMESTAMP(3) | 快照时间 |

**索引**：`INDEX(task_id, created_at)`。

---

### 4.18 `df_graph_node` — 图谱节点（对齐 `MOCK_GRAPH.nodes`；可扩展 combo）

| 字段名 | 类型 | 空 | 默认值 | 中文说明 |
|--------|------|----|--------|----------|
| `id` | BIGINT UNSIGNED | NO | 自增 | 内部主键 |
| `snapshot_id` | BIGINT UNSIGNED | NO | — | 所属图谱快照 |
| `node_key` | VARCHAR(64) | NO | — | 图内节点键（如 n1，与边 source/target 一致） |
| `label` | VARCHAR(256) | NO | — | 节点展示名 |
| `combo_key` | VARCHAR(64) | YES | NULL | 分组 ID（对应 comboId） |
| `style_json` | JSON | YES | NULL | 颜色等样式 |
| `sort_order` | INT | NO | 0 | 排序 |

**索引**：`UNIQUE(snapshot_id, node_key)`。

---

### 4.19 `df_graph_edge` — 图谱边（对齐 `MOCK_GRAPH.edges`）

| 字段名 | 类型 | 空 | 默认值 | 中文说明 |
|--------|------|----|--------|----------|
| `id` | BIGINT UNSIGNED | NO | 自增 | 内部主键 |
| `snapshot_id` | BIGINT UNSIGNED | NO | — | 所属图谱快照 |
| `source_node_key` | VARCHAR(64) | NO | — | 起点节点键 |
| `target_node_key` | VARCHAR(64) | NO | — | 终点节点键 |
| `edge_label` | VARCHAR(128) | YES | NULL | 边类型标签（如 DEMO_REL） |
| `style_json` | JSON | YES | NULL | 线型、语义色（冲突红/共识蓝） |

**索引**：`INDEX(snapshot_id)`。

---

### 4.20 `df_ab_compare` — A/B 时空对比文案（对齐 `MOCK_COMPARE`）

| 字段名 | 类型 | 空 | 默认值 | 中文说明 |
|--------|------|----|--------|----------|
| `id` | BIGINT UNSIGNED | NO | 自增 | 内部主键 |
| `task_id` | BIGINT UNSIGNED | NO | — | 所属任务 |
| `run_id_a` | BIGINT UNSIGNED | YES | NULL | 时空 A 运行 ID（演进后可填） |
| `run_id_b` | BIGINT UNSIGNED | YES | NULL | 时空 B 运行 ID |
| `timeline_label` | VARCHAR(256) | YES | NULL | 时间轴对齐说明 |
| `branch_a_title` | VARCHAR(256) | NO | — | 分支 A 标题 |
| `branch_a_bullets_json` | JSON | NO | — | 分支 A 要点数组 |
| `branch_b_title` | VARCHAR(256) | NO | — | 分支 B 标题 |
| `branch_b_bullets_json` | JSON | NO | — | 分支 B 要点数组 |
| `updated_at` | DATETIME(3) | NO | CURRENT_TIMESTAMP(3) ON UPDATE | 更新时间 |

**索引**：`UNIQUE(task_id)` 或 `INDEX(task_id)`（若一任务多组对比则用复合唯一键）。

---

## 5. 与前端 Mock 数据映射表

| 前端来源 | 数据库落点 |
|----------|------------|
| `MOCK_TASKS[]` | `df_task` + `df_task_input`（summary/title/mode/phase/updated_at） |
| `createDraft()` 新建 | `df_task`（phase=`sandbox_ready`）+ 可选 `df_task_input` |
| `MOCK_AGENTS[taskId]` | `df_sandbox_agent`（`task_id` 关联 `df_task.id` 经 public_id 解析） |
| `MOCK_CHECKPOINTS` | `df_world_checkpoint` |
| `MOCK_CONCLUSIONS` | `df_conclusion` |
| `MOCK_REPORTS` | `df_report`（version_label / pdf_status / excerpt） |
| `MOCK_PIPELINE` | `df_run_stage` + `df_run_stage_tag`（需先有 `df_simulation_run`） |
| `MOCK_GRAPH` | `df_graph_snapshot` + `df_graph_node` + `df_graph_edge` |
| `MOCK_COMPARE` | `df_ab_compare` |
| 设置页演示字段 | `df_user_preference` |

---

## 6. MySQL 建表示例（含字段 COMMENT）

以下仅列 **核心表** 完整 DDL，其余表可按 §4 字段表同理编写 `COMMENT`。

```sql
CREATE TABLE `df_task` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '内部主键',
  `public_id` VARCHAR(64) NOT NULL COMMENT '对外任务编号，如 tsk-demo-aurora',
  `org_id` BIGINT UNSIGNED NULL COMMENT '所属组织 ID，多租户预留',
  `owner_user_id` BIGINT UNSIGNED NOT NULL COMMENT '任务负责人用户 ID',
  `title` VARCHAR(512) NOT NULL COMMENT '任务标题',
  `mode` VARCHAR(32) NOT NULL COMMENT '推演模式：PUBLIC_OPINION/ENTERPRISE 等',
  `phase` VARCHAR(32) NOT NULL DEFAULT 'draft' COMMENT '任务阶段：draft/sandbox_ready/running/paused/completed',
  `summary` VARCHAR(1024) NULL COMMENT '列表与概览摘要',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间 UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近更新时间 UTC',
  `deleted_at` DATETIME(3) NULL COMMENT '软删除时间，非空表示已删除',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_task_public_id` (`public_id`),
  KEY `idx_task_owner_updated` (`owner_user_id`, `updated_at`),
  KEY `idx_task_org_phase` (`org_id`, `phase`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='推演任务主表';

CREATE TABLE `df_world_checkpoint` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '内部主键',
  `public_id` VARCHAR(64) NOT NULL COMMENT '对外快照编号，如 cp-aurora-final',
  `task_id` BIGINT UNSIGNED NOT NULL COMMENT '所属任务内部 ID',
  `run_id` BIGINT UNSIGNED NULL COMMENT '所属推演运行内部 ID，可空',
  `label` VARCHAR(256) NOT NULL COMMENT '快照标题，如 T+48h 虚构峰值',
  `summary` VARCHAR(1024) NULL COMMENT '快照摘要说明',
  `world_state_uri` VARCHAR(1024) NULL COMMENT '完整世界状态对象存储 URI',
  `world_state_json` JSON NULL COMMENT '小体积状态可内联 JSON',
  `simulation_time_label` VARCHAR(128) NULL COMMENT '推演内时间标签',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '快照生成时间 UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_checkpoint_public_id` (`public_id`),
  KEY `idx_checkpoint_task_time` (`task_id`, `created_at`),
  KEY `idx_checkpoint_run` (`run_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='可续推演世界快照';
```

---

## 7. 修订记录

| 版本 | 日期 | 说明 |
|------|------|------|
| 1.0 | 2026-05-12 | 初版：对齐《前端开发文档》V1.1 与 `deepforge-web` mock 全量表设计；§6 补充 MySQL COMMENT 示例 |

---

**维护约定**：任何新增业务表、字段、枚举，请在本文件 **「表结构定义」与「枚举」** 中补充，并更新 **「修订记录」** 版本号与日期；迁移脚本仓库若与文档分离，请在迁移 PR 中引用本文档章节号。
