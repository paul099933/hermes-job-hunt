# hermes-job-hunt

基于 Hermes Agent + Kanban 的 6 阶段自动求职流水线。

## 架构
## 使用

```bash
# 1. 启动 Gateway
tmux new-session -d -s hermes-gateway 'hermes gateway run'

# 2. 确保 6 个 profile 的 provider 为 deepseek
for p in specifier researcher analyst writer coach reviewer; do
  hermes -p $p config set model.provider deepseek
done

# 3. 投递岗位
bash orchestrator.sh "AI产品经理" "成都" "10k"
验证记录
2026-05-20: MVP 通过 (11a2eb73, Python后端/北京)
2026-05-21: 第二次通过 (84a267b8, AI产品经理/成都)
部署说明
profiles/ 目录下的 SOUL.md 是模板文件，使用时应复制到：
~/.hermes/profiles/<profile_name>/SOUL.md
License
MIT
