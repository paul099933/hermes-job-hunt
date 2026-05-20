#!/bin/bash
set -e

JOB_DESC="${1:?错误: 请提供岗位描述，如 \"Python后端@字节跳动\"}"
LOCATION="${2:-未知}"
SALARY="${3:-未知}"

BATCH_ID=$(openssl rand -hex 4)
WORKSPACE="/home/agent/job-hunt/workspaces/${BATCH_ID}"
TENANT="job-hunt"

mkdir -p "$WORKSPACE"

echo "=== 批次: ${BATCH_ID} ==="
echo "岗位: ${JOB_DESC} | ${LOCATION} | ${SALARY}"
echo "目录: ${WORKSPACE}"
echo ""

echo "[1/6] specifier（需求解析）..."
T_SPEC=$(hermes kanban create "解析: ${JOB_DESC} [${BATCH_ID}]" \
    --assignee specifier \
    --tenant ${TENANT} \
    --body "岗位描述: ${JOB_DESC}\n城市: ${LOCATION}\n薪资: ${SALARY}\n解析为结构化搜索关键词，输出到 ${WORKSPACE}/spec.json" \
    --workspace "dir:${WORKSPACE}" \
    --json | jq -r '.id // empty')

[ -z "$T_SPEC" ] && echo "❌ 创建失败" && exit 1
echo "  → ${T_SPEC}"

echo "[2/6] researcher（搜集 JD）..."
T_RESEARCH=$(hermes kanban create "搜集: ${JOB_DESC} [${BATCH_ID}]" \
    --assignee researcher \
    --tenant ${TENANT} \
    --parent ${T_SPEC} \
    --body "从父任务 metadata 读取 spec.json，按关键词搜索 JD。输出到 ${WORKSPACE}/research.json" \
    --workspace "dir:${WORKSPACE}" \
    --json | jq -r '.id // empty')
echo "  → ${T_RESEARCH}"

echo "[3/6] analyst（公司尽调）..."
T_ANALYST=$(hermes kanban create "尽调: ${JOB_DESC} [${BATCH_ID}]" \
    --assignee analyst \
    --tenant ${TENANT} \
    --parent ${T_RESEARCH} \
    --body "从父任务 metadata 读取 research.json，逐条验证公司工商信息。输出到 ${WORKSPACE}/audit.json" \
    --workspace "dir:${WORKSPACE}" \
    --json | jq -r '.id // empty')
echo "  → ${T_ANALYST}"

echo "[4/6] writer（写求职材料）..."
T_WRITER=$(hermes kanban create "写材料: ${JOB_DESC} [${BATCH_ID}]" \
    --assignee writer \
    --tenant ${TENANT} \
    --parent ${T_ANALYST} \
    --body "从父任务 metadata 读取 audit.json，定制简历和求职信。输出到 ${WORKSPACE}/final/" \
    --workspace "dir:${WORKSPACE}" \
    --json | jq -r '.id // empty')
echo "  → ${T_WRITER}"

echo "[5/6] coach（面试辅导）..."
T_COACH=$(hermes kanban create "辅导: ${JOB_DESC} [${BATCH_ID}]" \
    --assignee coach \
    --tenant ${TENANT} \
    --parent ${T_WRITER} \
    --body "从父任务 metadata 读取简历，生成面试问答和模拟题。输出到 ${WORKSPACE}/final/interview_prep.md" \
    --workspace "dir:${WORKSPACE}" \
    --json | jq -r '.id // empty')
echo "  → ${T_COACH}"

echo "[6/6] reviewer（质量检查）..."
T_REVIEW=$(hermes kanban create "审查: ${JOB_DESC} [${BATCH_ID}]" \
    --assignee reviewer \
    --tenant ${TENANT} \
    --parent ${T_COACH} \
    --body "审查所有输出文件质量，标记问题。输出审查报告到 ${WORKSPACE}/final/review_report.md" \
    --workspace "dir:${WORKSPACE}" \
    --json | jq -r '.id // empty')
echo "  → ${T_REVIEW}"

echo ""
echo "=== 流水线创建完成 ==="
echo "依赖链: ${T_SPEC} → ${T_RESEARCH} → ${T_ANALYST} → ${T_WRITER} → ${T_COACH} → ${T_REVIEW}"
echo "工作目录: ${WORKSPACE}"
