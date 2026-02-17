#!/usr/bin/env bash
# slack-notifier.sh - Send Slack notifications via t0-hub MCP
# Part of speckit-ralph

CHANNEL="${1:-}"
MESSAGE="${2:-}"

if [[ -z "$CHANNEL" ]] || [[ -z "$MESSAGE" ]]; then
    echo "[Slack] Missing channel or message" >&2
    exit 1
fi

# Check for token
if [[ -z "${T0_HUB_TOKEN:-}" ]]; then
    echo "[Slack] T0_HUB_TOKEN not set - get JWT from t0-mcp-hub" >&2
    exit 1
fi

# Use t0-hub's Slack MCP to post message
response=$(curl -s -X POST "https://n8n.t-0.co/mcp/hub/invoke" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${T0_HUB_TOKEN}" \
    -d "{
        \"tool\": \"invoke_slack_mcp_tool\",
        \"arguments\": {
            \"name\": \"chat_postMessage\",
            \"arguments\": {
                \"channel\": \"$CHANNEL\",
                \"text\": \"$MESSAGE\"
            }
        }
    }" 2>&1)

if echo "$response" | grep -q "error\|unauthorized"; then
    echo "[Slack] Failed: $response" >&2
    exit 1
fi

echo "[Slack] Sent to $CHANNEL"
