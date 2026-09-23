#!/usr/bin/env bash
# 给 Cloudflare Worker 读写 Secret —— 不依赖终端里有 node / npx / 全局 wrangler
#
# 用法：
#   ./cf-secret.sh                                  # 默认：unlimited-transfer-api 写 UNLIMITED_SURF_API_KEY
#   ./cf-secret.sh WORKER_API_KEY                   # 写别的 secret
#   ./cf-secret.sh WORKER_API_KEY --delete          # 删除某个 secret
#   NAME=别的worker名 ./cf-secret.sh                # 换 Worker
#
# 执行后会提示你粘贴密钥值（输入不回显，不会被记进 shell 历史）。
set -euo pipefail
cd "$(dirname "$0")"

NAME="${NAME:-unlimited-transfer-api}"
KEY="${1:-UNLIMITED_SURF_API_KEY}"
ACTION="${2:-put}"

# --- 1. 找 node：先用 PATH 里的，没有就找 WorkBuddy 自带的 ---
NODE="$(command -v node 2>/dev/null || true)"
if [ -z "$NODE" ]; then
  NODE="$(ls -d "$HOME"/.workbuddy/binaries/node/versions/*/bin/node 2>/dev/null | sort -V | tail -1 || true)"
fi
if [ ! -x "$NODE" ]; then
  echo "❌ 找不到 node。装一个 Node，或让 WorkBuddy 处理。" >&2
  exit 1
fi

# --- 2. 找 wrangler：优先项目本地那份，避免联网下载 ---
WRANGLER="./node_modules/.bin/wrangler"
if [ ! -f "$WRANGLER" ]; then
  echo "❌ 项目里没有 wrangler，先执行：" >&2
  echo "   \"$NODE\" \"$(dirname "$NODE")/npm\" install" >&2
  exit 1
fi

# --- 3. 载入 Cloudflare 凭据（token 不进脚本本体）---
# 优先级：环境变量 CF_ENV_FILE > 项目内 .env > 云端巡检目录里那份 .env
ENV_FILE="${CF_ENV_FILE:-}"
if [ -z "$ENV_FILE" ]; then
  for cand in "./.env" "$HOME/WorkBuddy/2026-09-20-14-05-42/cloudflare-audit/.env"; do
    [ -f "$cand" ] && { ENV_FILE="$cand"; break; }
  done
fi
if [ -n "$ENV_FILE" ] && [ -f "$ENV_FILE" ]; then
  set -a; . "$ENV_FILE"; set +a
fi
if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
  echo "❌ 没有 CLOUDFLARE_API_TOKEN。" >&2
  echo "   设 CF_ENV_FILE 指向存放它的 .env，或先 export 出来。" >&2
  exit 1
fi
export CLOUDFLARE_API_TOKEN
[ -n "${CLOUDFLARE_ACCOUNT_ID:-}" ] && export CLOUDFLARE_ACCOUNT_ID

echo "Worker : $NAME"
echo "Secret : $KEY"
echo

if [ "$ACTION" = "--delete" ]; then
  "$NODE" "$WRANGLER" secret delete "$KEY" --name "$NAME"
else
  "$NODE" "$WRANGLER" secret put "$KEY" --name "$NAME"
fi

echo
echo "=== 当前 secret 列表 ==="
"$NODE" "$WRANGLER" secret list --name "$NAME" 2>&1 | grep -vE "^▲|macOS version|DevContainer|^$"
