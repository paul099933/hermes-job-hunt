#!/bin/bash
set -e

JOB_DESC="${1:?用法: $0 \"岗位\" [城市] [薪资]}"
LOCATION="${2:-未知}"
SALARY="${3:-未知}"

BATCH_ID=$(openssl rand -hex 4)
WORKSPACE="/home/agent/job-hunt/workspaces/${BATCH_ID}"
TENANT="job-hunt"

mkdir -p "$WORKSPACE"

# ─── 定义搜索平台列表（5个平台全部搜索）──
PLATFORM_LIST="高校就业网:site:*.edu.cn,鱼泡直聘:site:yupao.com,智联招聘:site:zhaopin.com,猎聘:site:liepin.com,前程无忧:site:51job.com"

echo "=== 批次: ${BATCH_ID} ==="
echo "岗位: ${JOB_DESC} | ${LOCATION} | ${SALARY}"
echo "目录: ${WORKSPACE}"
echo ""

# ─── 阶段 1: researcher（搜集岗位）──
echo "[1/4] researcher（搜集岗位）..."
T_RESEARCH=$(hermes kanban create "搜集: ${JOB_DESC} [${BATCH_ID}]" \
    --assignee researcher \
    --tenant ${TENANT} \
    --body "岗位描述: ${JOB_DESC}\n城市: ${LOCATION}\n薪资: ${SALARY}\n平台列表: ${PLATFORM_LIST}\n输出到 ${WORKSPACE}/research.json" \
    --workspace "dir:${WORKSPACE}" \
    --json | jq -r '.id // empty')

[ -z "$T_RESEARCH" ] && echo "❌ researcher 创建失败" && exit 1
echo "  → ${T_RESEARCH}"

# ─── 阶段 2: analyst（尽调过滤）──
echo "[2/4] analyst（尽调过滤）..."
T_ANALYST=$(hermes kanban create "尽调: ${JOB_DESC} [${BATCH_ID}]" \
    --assignee analyst \
    --tenant ${TENANT} \
    --parent ${T_RESEARCH} \
    --body "读取 researcher 输出的 JD 摘要，逐条判决：1）JD 直接风险（外包/派遣/无五险一金）直接 reject/caution；2）3次搜索验证司法风险、融资信息、官网信息；3）输出 recommend/caution/reject 判决。输出到 ${WORKSPACE}/audit.json" \
    --workspace "dir:${WORKSPACE}" \
    --json | jq -r '.id // empty')

[ -z "$T_ANALYST" ] && echo "❌ analyst 创建失败" && exit 1
echo "  → ${T_ANALYST}"

# ─── 轮询 analyst 完成 ──
echo ""
echo "⏳ 等待 analyst 尽调完成（预计 3-5 分钟）..."
MAX_WAIT=600
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
    STATUS=$(hermes kanban show ${T_ANALYST} --json 2>/dev/null | jq -r '.task.status')
    echo "$(date '+%H:%M:%S') analyst: ${STATUS}"
    [ "$STATUS" = "done" ] && break
    [ "$STATUS" = "blocked" ] && echo "❌ analyst 失败" && exit 1
    sleep 30
    ELAPSED=$((ELAPSED + 30))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "❌ 超时 10 分钟，analyst 未完成"
    exit 1
fi

# ─── 打印尽调报告 ──
echo ""
echo "=== 尽调结果 ==="
cat ${WORKSPACE}/audit.json 2>/dev/null | jq -r '.companies[] | "\(.company): \(.recommendation) — \(.recommendation_reason)"' || echo "⚠️ 无法读取 audit.json"

# ─── 阶段 3: writer（创建后立即阻塞，等待人工选择）──
echo ""
echo "[3/4] writer（写材料）— 等待人工选择..."
T_WRITER=$(hermes kanban create "写材料: ${JOB_DESC} [${BATCH_ID}]" \
    --assignee writer \
    --tenant ${TENANT} \
    --body "读取 ${WORKSPACE}/research.json 和 ${WORKSPACE}/audit.json。从评论区解析用户选择的公司。与 audit.json 匹配并跳过 reject。只处理 recommend/caution 公司，生成材料，同时写入 ${WORKSPACE}/selected_companies.json 供下游使用。输出到 ${WORKSPACE}/final/" \
    --workspace "dir:${WORKSPACE}" \
    --json | jq -r '.id // empty')

[ -z "$T_WRITER" ] && echo "❌ writer 创建失败" && exit 1
echo "  → ${T_WRITER}"

# 立即阻塞，防止 Gateway 空转 pickup
hermes kanban block ${T_WRITER} "review-required: 尽调完成，请在评论区选择要投递的公司"

# ─── 阶段 4: coach（父=writer，自动 todo）──
echo "[4/4] coach（面试辅导）..."
T_COACH=$(hermes kanban create "辅导: ${JOB_DESC} [${BATCH_ID}]" \
    --assignee coach \
    --tenant ${TENANT} \
    --parent ${T_WRITER} \
    --body "读取 ${WORKSPACE}/research.json、${WORKSPACE}/audit.json 和 ${WORKSPACE}/selected_companies.json。只对选中公司生成面试题库。输出到 ${WORKSPACE}/final/interview_prep.md" \
    --workspace "dir:${WORKSPACE}" \
    --json | jq -r '.id // empty')

echo "  → ${T_COACH}"

# ─── 操作说明 ──
echo ""
echo "────────────────────────────────────────────────────────"
echo "✅ 流水线创建完成，等待人工确认"
echo "────────────────────────────────────────────────────────"
echo ""
echo "依赖链: ${T_RESEARCH} → ${T_ANALYST} → [人工选择] → ${T_WRITER} → ${T_COACH}"
echo ""
echo "=== 下一步操作 ==="
echo "1. 查看详情:   hermes kanban show ${T_WRITER}"
echo ""
echo "2. 选择公司（必须严格按以下格式，包括冒号和逗号）:"
echo "   hermes kanban comment ${T_WRITER} \"选择: 公司A, 公司B\""
echo ""
echo "3. 解除阻塞:   hermes kanban unblock ${T_WRITER}"
echo ""
echo "⚠️  格式错误会导致 writer 重新阻塞，需再次 comment + unblock"
echo ""
echo "4. 查看进度:   hermes kanban list --tenant job-hunt"
echo ""
