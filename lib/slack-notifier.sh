#!/usr/bin/env bash
# slack-notifier.sh - Send Slack notifications via Incoming Webhook
# Part of speckit-ralph
#
# Configure with a Slack Incoming Webhook URL:
#   export RALPH_SLACK_WEBHOOK_URL="https://hooks.slack.com/services/T.../B.../xxx"
#
# See: https://api.slack.com/messaging/webhooks

CHANNEL="${1:-}"
MESSAGE="${2:-}"

if [[ -z "$CHANNEL" ]] || [[ -z "$MESSAGE" ]]; then
    echo "[Slack] Missing channel or message" >&2
    exit 1
fi

# Check for webhook URL
SLACK_WEBHOOK_URL="${RALPH_SLACK_WEBHOOK_URL:-}"
if [[ -z "$SLACK_WEBHOOK_URL" ]]; then
    echo "[Slack] RALPH_SLACK_WEBHOOK_URL not set - configure a Slack Incoming Webhook URL" >&2
    exit 1
fi

# Post message via Slack Incoming Webhook
response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$SLACK_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "{
        \"channel\": \"$CHANNEL\",
        \"text\": \"$MESSAGE\"
    }" 2>&1)

if [[ "$response" != "200" ]]; then
    echo "[Slack] Failed with HTTP $response" >&2
    exit 1
fi

echo "[Slack] Sent to $CHANNEL"
