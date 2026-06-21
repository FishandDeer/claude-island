#!/bin/zsh
set -u

BASE_DIR="${HOME}/.claude/claude-island"
STATUS_FILE="${BASE_DIR}/status.json"
EVENT_NAME="${CLAUDE_HOOK_EVENT:-${1:-unknown}}"

mkdir -p "$BASE_DIR"

state="running"
case "$EVENT_NAME" in
  SessionStart)
    state="ready"
    ;;
  SessionEnd)
    state="offline"
    ;;
  UserPromptSubmit)
    state="thinking"
    ;;
  PreToolUse|PostToolUse|SubagentStart)
    state="running"
    ;;
  Notification)
    state="waiting"
    ;;
  PermissionRequest|PermissionDenied|Permission|PermissionPrompt|Approval|ApprovalRequest)
    state="permission"
    ;;
  Stop|SubagentStop)
    state="ready"
    ;;
  PostToolUseFailure|StopFailure|UserPromptSubmit:error|PreToolUse:error|PostToolUse:error|Notification:error|Stop:error|SubagentStop:error)
    state="error"
    ;;
  *)
    state="running"
    ;;
esac

timestamp="$(date +%s)"
tmp_file="${STATUS_FILE}.$$"

cat > "$tmp_file" <<JSON
{
  "state": "${state}",
  "updatedAt": ${timestamp},
  "event": "${EVENT_NAME}"
}
JSON

mv "$tmp_file" "$STATUS_FILE"
