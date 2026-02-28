#!/bin/bash

# NATS Cluster Test — docker compose wrapper
# Builds and runs the publisher/subscriber/k6 stack in nats-load-test/

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="${SCRIPT_DIR}/nats-load-test"
COMPOSE="docker compose -f ${COMPOSE_DIR}/docker-compose.yml"

# ── Helpers ───────────────────────────────────────────────────────────────────
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] ${message}${NC}"
}

print_section() {
    local title=$1
    local line="═══════════════════════════════════════════════════════════════"
    local title_len=${#title}
    local line_len=${#line}
    local spaces=$(( (line_len - title_len - 2) / 2 ))
    local padding=""
    for ((i=0; i<spaces; i++)); do padding+=" "; done
    echo
    echo -e "${CYAN}${BOLD}╔${line}╗${NC}"
    echo -e "${CYAN}${BOLD}║${padding}${title}${padding}$([ $(( (line_len - title_len) % 2 )) -eq 1 ] && echo " ")║${NC}"
    echo -e "${CYAN}${BOLD}╚${line}╝${NC}"
}

teardown() {
    print_status $BLUE "Stopping containers..."
    $COMPOSE down --remove-orphans 2>/dev/null || true
}

# ── Commands ──────────────────────────────────────────────────────────────────

cmd_build() {
    print_section "BUILD"
    print_status $BLUE "Building images..."
    $COMPOSE build
    print_status $GREEN "✓ Images built"
}

cmd_test() {
    local vus="${VUS:-10}"
    local duration="${DURATION:-60s}"
    local pub_replicas="${PUBLISHER_REPLICAS:-10}"
    local sub_replicas="${SUBSCRIBER_REPLICAS:-10}"

    print_section "LOAD TEST"
    print_status $BLUE "Starting subscriber (x${sub_replicas}) and publisher (x${pub_replicas})..."
    $COMPOSE up -d \
        --scale publisher="$pub_replicas" \
        --scale subscriber="$sub_replicas" \
        subscriber publisher

    # Wait for ALL publisher replicas to report healthy
    print_status $BLUE "Waiting for all ${pub_replicas} publisher replicas to be healthy..."
    local retries=40
    for ((i=1; i<=retries; i++)); do
        local total healthy
        total=$($COMPOSE ps -q publisher 2>/dev/null | wc -l | tr -d ' ')
        healthy=$(docker inspect $($COMPOSE ps -q publisher 2>/dev/null) 2>/dev/null \
            | python3 -c "import sys,json; data=json.load(sys.stdin); print(sum(1 for c in data if c.get('State',{}).get('Health',{}).get('Status') == 'healthy'))" 2>/dev/null || echo 0)
        if [[ "$healthy" -ge "$pub_replicas" ]]; then
            print_status $GREEN "✓ All ${pub_replicas} publisher replicas are healthy"
            break
        fi
        if [[ $i -eq $retries ]]; then
            print_status $RED "✗ Publishers did not become healthy in time (${healthy}/${pub_replicas} healthy) — aborting"
            teardown
            exit 1
        fi
        print_status $YELLOW "  Healthy: ${healthy}/${pub_replicas} ($i/$retries)"
        sleep 3
    done

    print_section "K6 LOAD TEST  (VUs=${vus}  duration=${duration})"
    echo -e "${YELLOW}Subscriber logs will appear interleaved — k6 summary appears at the end.${NC}"
    echo

    $COMPOSE run --rm \
        -e VUS="${vus}" \
        -e DURATION="${duration}" \
        k6
    local exit_code=$?

    print_section "SUBSCRIBER STATS (last 10 lines)"
    $COMPOSE logs --tail 10 subscriber

    teardown

    if [[ $exit_code -eq 0 ]]; then
        print_status $GREEN "✓ Load test completed — all thresholds passed"
    else
        print_status $RED "✗ Load test finished with threshold failures (exit ${exit_code})"
    fi

    return $exit_code
}

cmd_status() {
    print_section "STACK STATUS"

    print_status $BLUE "Container state:"
    $COMPOSE ps 2>/dev/null || print_status $YELLOW "  (no containers running)"

    echo
    print_status $BLUE "Publisher health (all replicas):"
    local healthy total
    total=$($COMPOSE ps -q publisher 2>/dev/null | wc -l | tr -d ' ')
    healthy=$(docker inspect $($COMPOSE ps -q publisher 2>/dev/null) 2>/dev/null \
        | python3 -c "import sys,json; data=json.load(sys.stdin); print(sum(1 for c in data if c.get('State',{}).get('Health',{}).get('Status') == 'healthy'))" 2>/dev/null || echo 0)
    if [[ "$total" -gt 0 ]]; then
        print_status $GREEN "  Healthy: ${healthy}/${total}"
    else
        print_status $YELLOW "  Publisher not running"
    fi

    echo
    print_status $BLUE "Subscriber logs (last 5 lines, all replicas):"
    $COMPOSE logs --tail 5 subscriber 2>/dev/null \
        || print_status $YELLOW "  (subscriber not running)"
}

cmd_interactive() {
    print_section "INTERACTIVE MODE"
    local pub_replicas="${PUBLISHER_REPLICAS:-10}"
    local sub_replicas="${SUBSCRIBER_REPLICAS:-10}"

    print_status $BLUE "Starting subscriber (x${sub_replicas}) and publisher (x${pub_replicas}) in background..."
    $COMPOSE up -d \
        --scale publisher="$pub_replicas" \
        --scale subscriber="$sub_replicas" \
        subscriber publisher

    print_status $BLUE "Waiting for publishers to be healthy..."
    local retries=40
    for ((i=1; i<=retries; i++)); do
        local total healthy
        total=$($COMPOSE ps -q publisher 2>/dev/null | wc -l | tr -d ' ')
        healthy=$(docker inspect $($COMPOSE ps -q publisher 2>/dev/null) 2>/dev/null \
            | python3 -c "import sys,json; data=json.load(sys.stdin); print(sum(1 for c in data if c.get('State',{}).get('Health',{}).get('Status') == 'healthy'))" 2>/dev/null || echo 0)
        if [[ "$healthy" -ge "$pub_replicas" ]]; then
            print_status $GREEN "✓ All ${pub_replicas} publisher replicas ready"
            break
        fi
        [[ $i -eq $retries ]] && { print_status $RED "✗ Publishers not ready (${healthy}/${pub_replicas})"; teardown; exit 1; }
        print_status $YELLOW "  Healthy: ${healthy}/${pub_replicas} ($i/$retries)"
        sleep 3
    done

    echo
    echo -e "${BOLD}Stack is running. Send a test message (exec into a publisher container):${NC}"
    echo -e "${GREEN}─────────────────────────────────────────────────────────────${NC}"
    echo -e "${BOLD}docker compose -f ${COMPOSE_DIR}/docker-compose.yml exec publisher \\
  wget -qO- --post-data='{\"payload\":\"hello\"}' \\
  --header='Content-Type:application/json' localhost:3000/publish${NC}"
    echo -e "${GREEN}─────────────────────────────────────────────────────────────${NC}"
    echo
    echo -e "${YELLOW}Tailing subscriber logs — messages arriving from cace-2-dev appear here.${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop and tear down.${NC}"
    echo

    trap teardown INT TERM
    $COMPOSE logs -f subscriber
}

usage() {
    echo -e "${CYAN}${BOLD}NATS Cluster Test — docker compose wrapper${NC}"
    echo
    echo -e "${YELLOW}${BOLD}Usage:${NC}"
    echo "  $0 [command] [options]"
    echo
    echo -e "${YELLOW}${BOLD}Commands:${NC}"
    echo -e "  ${BOLD}build${NC}        Build (or rebuild) container images"
    echo -e "  ${BOLD}test${NC}         Run load test: subscriber + publisher + k6  (default)"
    echo -e "  ${BOLD}status${NC}       Show running container state and publisher health"
    echo -e "  ${BOLD}interactive${NC}  Start subscriber/publisher and tail subscriber logs"
    echo -e "  ${BOLD}down${NC}         Stop and remove all containers"
    echo -e "  ${BOLD}help${NC}         Show this message"
    echo
    echo -e "${YELLOW}${BOLD}Load test env overrides:${NC}"
    echo "  VUS=<n>                   Concurrent virtual users           (default: 10)"
    echo "  DURATION=<time>           Test duration, e.g. 30s            (default: 60s)"
    echo "  PUBLISHER_REPLICAS=<n>    Number of publisher containers     (default: 10)"
    echo "  SUBSCRIBER_REPLICAS=<n>   Number of subscriber containers    (default: 10)"
    echo
    echo -e "${YELLOW}${BOLD}Examples:${NC}"
    echo "  $0                                              # Build (if needed) and run load test"
    echo "  $0 build                                        # Only build images"
    echo "  VUS=50 DURATION=120s $0 test                   # 50 VUs for 2 minutes"
    echo "  PUBLISHER_REPLICAS=3 SUBSCRIBER_REPLICAS=2 $0  # Scale out publisher and subscriber"
    echo "  $0 interactive                                  # Manual publish/subscribe"
    echo "  $0 status                                       # Check what is running"
    echo "  $0 down                                         # Clean up"
}

# ── Entrypoint ────────────────────────────────────────────────────────────────
main() {
    local cmd="${1:-test}"

    # Auto-build if images are missing
    case "$cmd" in
        test|interactive)
            if ! docker image inspect nats-load-test-k6 &>/dev/null \
            || ! docker image inspect nats-load-test-publisher &>/dev/null \
            || ! docker image inspect nats-load-test-subscriber &>/dev/null; then
                print_status $YELLOW "One or more images not found — building first..."
                cmd_build
            fi
            ;;
    esac

    case "$cmd" in
        build)       cmd_build ;;
        test)        cmd_test ;;
        status)      cmd_status ;;
        interactive) cmd_interactive ;;
        down)        teardown; print_status $GREEN "✓ Done" ;;
        help|-h|--help) usage ;;
        *)
            print_status $RED "Unknown command: $cmd"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

main "$@"
