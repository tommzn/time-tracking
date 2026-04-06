#!/usr/bin/env bash
# mqtt-publish.sh — publish a time-tracking IoT event to a HiveMQ broker
#
# Usage:
#   ./mqtt-publish.sh <action>
#
#   action:  single_tap  →  working time
#            double_tap  →  sickness
#            long_tap    →  vacation
#
# Configuration (environment variables, or edit the defaults below):
#   MQTT_HOST   broker hostname   e.g. abc123.s2.eu.hivemq.cloud
#   MQTT_PORT   broker port       default: 8883
#   MQTT_TOPIC  publish topic     default: time/events
#   MQTT_USER   username          default: (empty)
#   MQTT_PASS   password          default: (empty)
#   MQTT_TLS    use TLS           default: true
#
# Example with inline env vars:
#   MQTT_HOST=abc123.s2.eu.hivemq.cloud \
#   MQTT_USER=myuser MQTT_PASS=secret \
#   ./mqtt-publish.sh single_tap
#
# Requires: mosquitto_pub  →  brew install mosquitto

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
MQTT_HOST="${MQTT_HOST:-your-broker.s2.eu.hivemq.cloud}"
MQTT_PORT="${MQTT_PORT:-8883}"
MQTT_TOPIC="${MQTT_TOPIC:-time/events}"
MQTT_USER="${MQTT_USER:-}"
MQTT_PASS="${MQTT_PASS:-}"
MQTT_TLS="${MQTT_TLS:-true}"

# ── Validate action ───────────────────────────────────────────────────────────
ACTION="${1:-}"
case "$ACTION" in
  single_tap|double_tap|long_tap) ;;
  *)
    echo "Usage: $(basename "$0") <action>"
    echo ""
    echo "  single_tap  →  working time"
    echo "  double_tap  →  sickness"
    echo "  long_tap    →  vacation"
    exit 1
    ;;
esac

# ── Check dependency ──────────────────────────────────────────────────────────
if ! command -v mosquitto_pub &>/dev/null; then
  echo "Error: mosquitto_pub not found."
  echo "Install with:  brew install mosquitto"
  exit 1
fi

# ── Build payload ─────────────────────────────────────────────────────────────
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
PAYLOAD="{\"action\":\"${ACTION}\",\"timestamp\":\"${TIMESTAMP}\"}"

# ── Build mosquitto_pub arguments ─────────────────────────────────────────────
ARGS=(-h "$MQTT_HOST" -p "$MQTT_PORT" -t "$MQTT_TOPIC" -m "$PAYLOAD" -q 1)

[[ -n "$MQTT_USER" ]] && ARGS+=(-u "$MQTT_USER")
[[ -n "$MQTT_PASS" ]] && ARGS+=(-P "$MQTT_PASS")
[[ "$MQTT_TLS"    == "true" ]] && ARGS+=(--tls-use-os-certs)

# ── Publish ───────────────────────────────────────────────────────────────────
echo "→ ${MQTT_HOST}:${MQTT_PORT}  topic: ${MQTT_TOPIC}"
echo "  ${PAYLOAD}"
mosquitto_pub "${ARGS[@]}"
echo "✓ published"
