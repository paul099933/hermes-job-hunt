# hermes-job-hunt

基于 Hermes Agent + Kanban 的 **4 阶段决策辅助求职流水线**。

本系统不是全自动投递机器人，而是**人机协作的决策辅助工具**：
- **目标 1**：自动收集公司情报并过滤，辅助你做出投递决策
- **目标 2**：为确认投递的公司自动生成定制化简历、求职信和面试题库

所有关键决策点（选择公司）**必须人工确认**，系统不会自动投递任何岗位。

---

## 架构

```
用户输入 → researcher → analyst → [人工确认] → writer → coach
```

### Agent 职责

| Agent | 职责 | 输入 | 输出 | 是否自动 |
|-------|------|------|------|---------|
| **researcher** | 搜索并收集 JD 和公司列表 | task body（岗位/城市/薪资） | `research.json` | ✅ |
| **analyst** | 逐条尽调，标记 recommend/caution/reject | `research.json` | `audit.json` | ✅ |
| **[人工]** | 查看尽调结果，决定投递哪些公司 | `audit.json` | Kanban Comment | 🔴 **必须人工** |
| **writer** | 为选中公司生成简历和求职信 | `audit.json` + 用户 Comment | `final/01_公司名/` | ✅ |
| **coach** | 生成定向面试题库 | `research.json` + `audit.json` + `selected_companies.json` | `final/interview_prep.md` | ✅ |

### 已删除的 Agent

旧版有 6 个 Agent，新架构精简为 4 个：
- ❌ **specifier**：仅做字符串转 JSON，无独立价值
- ❌ **reviewer**：形式审查多余，writer 输出可直接人工查看

---

## 人工确认与数据输入

核心设计：**"机器搜集情报 → 人工决策 → 机器生成材料"**

### 1. 启动时：输入岗位信息

```bash
bash /home/agent/job-hunt/orchestrator.sh "AI产品经理" "成都" "10k"
```

参数：
- `$1`（必填）：岗位描述，如 `"AI产品经理"`
- `$2`（可选）：城市，如 `"成都"`。不填则 `"未知"`
- `$3`（可选）：期望薪资，如 `"10k"`。不填则 `"未知"`

> ⚠️ 薪资目前为**定性参考**。招聘网站薪资多为字符串（如 `"25-35k"`、`"面议"`、`"12-20K·16薪"`），无法可靠解析为数字，analyst 过滤以定性描述为主。

### 2. 关键决策点：选择公司（BLOCK → COMMENT → UNBLOCK）

这是唯一必须人工操作的环节。analyst 完成后，writer 任务会**自动阻塞**。

**操作步骤**：

```bash
# 1. 查看尽调结果（可选）
cat /home/agent/job-hunt/workspaces/<BATCH_ID>/audit.json | jq '.companies[] | {company, recommendation, recommendation_reason}'

# 2. 评论选择公司
# ⚠️ 必须严格使用 "选择:" 前缀，用逗号/空格/顿号分隔
hermes kanban comment <WRITER_TASK_ID> "选择: 字节跳动, 美团, 小红书"

# 3. 解除阻塞
hermes kanban unblock <WRITER_TASK_ID>
```

**解析与匹配规则**：
- 取 comments 数组**最后一条**
- 必须含 `"选择:"`，否则 writer **自动重新 block** 并提示格式错误
- 匹配：精确匹配 → 子串匹配（如 `"京东科技"` 匹配 `"北京京东科技有限公司"`）→ 失败则记为 `"未匹配"`

### 3. 二次拦截：自动跳过 reject 公司

writer 会**自动跳过** `recommendation=reject` 的公司，即使被用户选中。只处理 `recommend` 和 `caution` 的公司。被跳过的公司写入 `final/00_排除说明.md`。

### 4. 查看生成结果

```
workspaces/<BATCH_ID>/final/
├── 01_字节跳动/
│   ├── resume.md          # 定制化简历（突出该公司技能关键词）
│   └── cover_letter.md    # caution 公司末尾含风险提示
├── 02_美团/
│   ├── resume.md
│   └── cover_letter.md
├── interview_prep.md      # 定向面试题库
├── 00_排除说明.md
└── 00_未匹配说明.md
```

---

## 运行方式

### 前置条件

```bash
# 1. 启动 Gateway
tmux new-session -d -s hermes-gateway 'hermes gateway run'

# 2. 配置 4 个 profile
for p in researcher analyst writer coach; do
  hermes -p $p config set model.provider deepseek
done
```

### 完整流程

```bash
# 步骤 1: 启动（自动运行 researcher → analyst）
bash /home/agent/job-hunt/orchestrator.sh "AI产品经理" "成都" "10k"

# 输出会显示：
# - BATCH_ID 和工作区路径
# - researcher / analyst 的 task_id
# - 尽调结果摘要
# - writer task_id（已 block）
# - coach task_id
# - 下一步操作提示

# 步骤 2: 人工选择并解除阻塞
hermes kanban comment <WRITER_ID> "选择: 字节跳动, 小红书"
hermes kanban unblock <WRITER_ID>

# 步骤 3: 等待 writer + coach 完成（2-3 分钟）

# 步骤 4: 查看结果
ls /home/agent/job-hunt/workspaces/<BATCH_ID>/final/
```

---

## 为什么这样设计？

### Kanban Comment + Unblock vs 文件编辑 / shell read

| 方案 | 问题 | 结论 |
|------|------|------|
| 文件编辑 | tmux 环境编辑困难，易格式错误 | ❌ 不用 |
| shell read | tmux 非交互环境不支持 | ❌ 不用 |
| **Kanban Comment + Unblock** | 非阻塞、可追溯、格式可校验、tmux 安全 | ✅ **采用** |

### writer 从 Comment 读取 vs 从文件读取

旧版需要用户手写 `selected_companies.json` 再手动触发 Phase 2。新版 writer 创建即 block，用户 Comment 后直接自动解析生成，无需手动编辑 JSON，格式错误时自动重 block 并提示。

### coach 基于岗位要求 vs 基于简历

面试题应针对 **"岗位技能要求"** 和 **"公司面试情报"** 生成，而非你的简历，这样题目才具有实战价值。

---

## 搜索熔断（成本保护）

| Agent | 限制 | 失败处理 |
|-------|------|---------|
| researcher | 2 次 web_search/岗位 | 记录 not_found，不阻塞 |
| analyst | 4 次 search+extract/公司 | status: search_failed，继续下一家 |

---

## 目录结构

```
job-hunt/
├── orchestrator.sh              # 启动脚本
├── workspaces/
│   └── <BATCH_ID>/
│       ├── research.json        # 岗位列表
│       ├── audit.json           # 尽调结果
│       ├── selected_companies.json   # writer 写入的选择结果
│       └── final/               # 生成材料
├── resumes/                     # 历史简历/模板
├── outbox/                      # 手动投递材料（系统不自动投递）
└── backup/                      # 备份
```

---

## 验证记录

- 2026-05-20: MVP 通过 (11a2eb73, Python后端/北京)
- 2026-05-21: 第二次通过 (84a267b8, AI产品经理/成都)
- 2026-05-25: 重构为 4-Agent 决策辅助流水线，删除 specifier/reviewer

## License

MIT
