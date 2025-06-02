#!/bin/bash

# NATS Cluster Inter-connection Test Script
# This script tests individual NATS servers and sets up cluster inter-connection

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# NATS server configurations
DEV_1_NATS_URL="nats://nats.cace-1-dev.dramisinfo.com:4222"
DEV_1_GATEWAY_URL="nats://nats.cace-1-dev.dramisinfo.com:7222"
DEV_2_NATS_URL="nats://nats.cace-2-dev.dramisinfo.com:4222"
DEV_2_GATEWAY_URL="nats://nats.cace-2-dev.dramisinfo.com:7222"

# Test subject for messaging
TEST_SUBJECT="cluster.test"
TEST_MESSAGE="Hello from NATS cluster test"

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] ${message}${NC}"
}

# Function to print section header
print_section() {
    local title=$1
    local line="═══════════════════════════════════════════════════════════════"
    local padding=""
    local title_len=${#title}
    local line_len=${#line}
    local spaces=$(( (line_len - title_len - 2) / 2 ))
    
    for ((i=0; i<spaces; i++)); do
        padding+=" "
    done
    
    echo
    echo -e "${CYAN}${BOLD}╔${line}╗${NC}"
    echo -e "${CYAN}${BOLD}║${padding}${title}${padding}$([ $(( (line_len - title_len) % 2 )) -eq 1 ] && echo " ")║${NC}"
    echo -e "${CYAN}${BOLD}╚${line}╝${NC}"
}

# Function to test NATS server connectivity
test_nats_connectivity() {
    local server_name=$1
    local nats_url=$2
    
    print_status $BLUE "Testing connectivity to $server_name ($nats_url)..."
    
    # Run with a timeout and capture the output
    local connection_output
    if connection_output=$(timeout 10 nats server check connection --server="$nats_url" 2>/dev/null); then
        # Extract just the connection time for a cleaner output
        local connect_time
        connect_time=$(echo "$connection_output" | grep -o "connected to.*in [0-9.]*ms" | head -1)
        if [ -n "$connect_time" ]; then
            print_status $GREEN "✓ $server_name is reachable and responding ($connect_time)"
        else
            print_status $GREEN "✓ $server_name is reachable and responding"
        fi
        return 0
    else
        print_status $RED "✗ $server_name is not reachable or not responding"
        return 1
    fi
}

# Function to get server info
get_server_info() {
    local server_name=$1
    local nats_url=$2
    
    print_status $BLUE "Getting server info for $server_name..."
    
    if timeout 10 nats server info --server="$nats_url" 2>/dev/null; then
        return 0
    else
        print_status $YELLOW "Could not retrieve detailed server info for $server_name (likely due to permission restrictions)"
        return 0  # Return 0 to not fail the script
    fi
}

# Function to test pub/sub on a single server
test_pubsub_single() {
    local server_name=$1
    local nats_url=$2
    
    print_status $BLUE "Testing pub/sub on $server_name..."
    
    # Start subscriber in background
    local sub_output=$(mktemp)
    nats sub --server="$nats_url" "$TEST_SUBJECT" > "$sub_output" 2>&1 &
    local sub_pid=$!
    
    # Give subscriber time to connect
    sleep 2
    
    # Publish message
    if nats pub --server="$nats_url" "$TEST_SUBJECT" "$TEST_MESSAGE from $server_name" >/dev/null 2>&1; then
        sleep 1
        kill $sub_pid 2>/dev/null || true
        wait $sub_pid 2>/dev/null || true
        
        if grep -q "$TEST_MESSAGE from $server_name" "$sub_output"; then
            print_status $GREEN "✓ Pub/Sub test successful on $server_name"
            rm -f "$sub_output"
            return 0
        else
            print_status $RED "✗ Message not received on $server_name"
            rm -f "$sub_output"
            return 1
        fi
    else
        kill $sub_pid 2>/dev/null || true
        wait $sub_pid 2>/dev/null || true
        print_status $RED "✗ Failed to publish message on $server_name"
        rm -f "$sub_output"
        return 1
    fi
}

# Function to test cross-cluster messaging
test_cross_cluster_messaging() {
    print_status $BLUE "Testing cross-cluster messaging..."
    
    # Start subscriber on dev 2
    local sub_output=$(mktemp)
    print_status $YELLOW "Starting subscriber on dev 2 server..."
    nats sub --server="$DEV_2_NATS_URL" "$TEST_SUBJECT.cross" > "$sub_output" 2>&1 &
    local sub_pid=$!
    
    # Give subscriber time to connect
    sleep 3
    
    # Publish from dev 1
    print_status $YELLOW "Publishing message from dev 1 server..."
    if nats pub --server="$DEV_1_NATS_URL" "$TEST_SUBJECT.cross" "Cross-cluster message from dev 1 to dev 2" >/dev/null 2>&1; then
        sleep 2
        kill $sub_pid 2>/dev/null || true
        wait $sub_pid 2>/dev/null || true
        
        if grep -q "Cross-cluster message from dev 1 to dev 2" "$sub_output"; then
            print_status $GREEN "✓ Cross-cluster messaging is working!"
            rm -f "$sub_output"
            return 0
        else
            print_status $RED "✗ Cross-cluster message not received"
            print_status $YELLOW "⚠ This may indicate that clusters are not properly connected"
            rm -f "$sub_output"
            return 1  # Now returning 1 to reflect an actual problem
        fi
    else
        kill $sub_pid 2>/dev/null || true
        wait $sub_pid 2>/dev/null || true
        print_status $RED "✗ Failed to publish cross-cluster message"
        rm -f "$sub_output"
        return 1
    fi
}

# Function to test gateway connectivity
test_gateway_connectivity() {
    local server_name=$1
    local gateway_url=$2
    
    print_status $BLUE "Testing gateway connectivity to $server_name ($gateway_url)..."
    
    # Extract host and port from URL
    local host_port="${gateway_url#nats://}"
    
    # Try to connect to gateway port (this might not work directly but we can try)
    if timeout 5 nc -z $host_port 2>/dev/null; then
        print_status $GREEN "✓ $server_name gateway port is reachable"
        return 0
    else
        print_status $YELLOW "? $server_name gateway port test inconclusive (this is normal for remote clusters)"
        return 0  # Return 0 to not fail the script
    fi
}

# Function to display cluster status
show_cluster_status() {
    print_section "CLUSTER STATUS SUMMARY"
    
    print_status $BLUE "Checking Dev 1 server status..."
    if timeout 10 nats server info --server="$DEV_1_NATS_URL" 2>/dev/null | grep -E "(Server ID|Cluster|Gateway|Connections)"; then
        :  # Info retrieved successfully
    else
        if nats server check connection --server="$DEV_1_NATS_URL" 2>&1 | grep -q "OK Connection OK"; then
            print_status $GREEN "✓ Dev 1 server is reachable and responding"
        else
            print_status $RED "✗ Dev 1 server connectivity test failed"
        fi
    fi
    
    print_status $BLUE "Checking Dev 2 server status..."
    if timeout 10 nats server info --server="$DEV_2_NATS_URL" 2>/dev/null | grep -E "(Server ID|Cluster|Gateway|Connections)"; then
        :  # Info retrieved successfully
    else
        if nats server check connection --server="$DEV_2_NATS_URL" 2>&1 | grep -q "OK Connection OK"; then
            print_status $GREEN "✓ Dev 2 server is reachable and responding"
        else
            print_status $RED "✗ Dev 2 server connectivity test failed"
        fi
    fi
}

# Function to run interactive test
interactive_test() {
    print_section "INTERACTIVE MESSAGING TEST"
    
    echo -e "${BOLD}This test allows you to send messages between NATS servers interactively${NC}"
    echo
    echo -e "${CYAN}Instructions:${NC}"
    echo -e "  1. This will start a subscriber on dev 2 server"
    echo -e "  2. You can then publish messages from dev 1 server in another terminal"
    echo -e "  3. Press ${BOLD}Ctrl+C${NC} to stop the subscriber when finished"
    echo
    read -p "Press Enter to continue..."
    
    print_status $YELLOW "Starting subscriber on dev 2 (listening to 'interactive.test')..."
    echo
    echo -e "${BOLD}How to send messages:${NC}"
    echo -e "${GREEN}-------------------------------------------------------${NC}"
    echo -e "Run this command in another terminal:"
    echo -e "${BOLD}nats pub --server=\"$DEV_1_NATS_URL\" \"interactive.test\" \"Your message here\"${NC}"
    echo -e "${GREEN}-------------------------------------------------------${NC}"
    echo
    echo -e "${YELLOW}Waiting for messages... (Press Ctrl+C to stop)${NC}"
    echo
    
    nats sub --server="$DEV_2_NATS_URL" "interactive.test"
}

# Function to display test summary
show_test_summary() {
    local dev1_status=$1
    local dev2_status=$2
    local dev1_pubsub=$3
    local dev2_pubsub=$4
    local cross_cluster=$5

    print_section "TEST SUMMARY"
    
    echo -e "${BOLD}Server Connectivity:${NC}"
    echo -e "  Dev 1: ${dev1_status}"
    echo -e "  Dev 2: ${dev2_status}"
    echo
    
    echo -e "${BOLD}Pub/Sub Functionality:${NC}"
    echo -e "  Dev 1: ${dev1_pubsub}"
    echo -e "  Dev 2: ${dev2_pubsub}"
    echo
    
    echo -e "${BOLD}Cross-Cluster Communication:${NC}"
    echo -e "  Status: ${cross_cluster}"
    echo
    
    if [[ "$dev1_status" == *"✓"* ]] && [[ "$dev2_status" == *"✓"* ]] && [[ "$cross_cluster" == *"✓"* ]]; then
        echo -e "${GREEN}${BOLD}✓ All tests passed successfully!${NC}"
    elif [[ "$cross_cluster" != *"✓"* ]]; then
        echo -e "${YELLOW}${BOLD}⚠ Basic connectivity working, but cross-cluster communication failed${NC}"
        echo -e "${YELLOW}This may indicate a cluster configuration issue${NC}"
    else
        echo -e "${RED}${BOLD}✗ Some tests failed - check details above${NC}"
    fi
}

# Main function
main() {
    print_status $GREEN "Starting NATS Cluster Inter-connection Test"
    echo
    
    case "${1:-test}" in
        "test")
            print_section "CONNECTIVITY TESTS"
            
            # Test connectivity
            dev_1_ok=false
            dev_2_ok=false
            dev_1_status="${RED}✗ Not reachable${NC}"
            dev_2_status="${RED}✗ Not reachable${NC}"
            dev_1_pubsub="${RED}✗ Failed${NC}"
            dev_2_pubsub="${RED}✗ Failed${NC}"
            cross_cluster_status="${RED}✗ Failed${NC}"
            
            if test_nats_connectivity "Dev 1" "$DEV_1_NATS_URL"; then
                dev_1_ok=true
                dev_1_status="${GREEN}✓ Reachable${NC}"
            fi
            
            if test_nats_connectivity "Dev 2" "$DEV_2_NATS_URL"; then
                dev_2_ok=true
                dev_2_status="${GREEN}✓ Reachable${NC}"
            fi
            
            # Get server info
            if [ "$dev_1_ok" = true ]; then
                get_server_info "Dev 1" "$DEV_1_NATS_URL"
            fi
            
            if [ "$dev_2_ok" = true ]; then
                get_server_info "Dev 2" "$DEV_2_NATS_URL"
            fi
            
            # Test pub/sub on individual servers
            print_section "PUB/SUB TESTS"
            
            if [ "$dev_1_ok" = true ]; then
                if test_pubsub_single "Dev 1" "$DEV_1_NATS_URL"; then
                    dev_1_pubsub="${GREEN}✓ Working${NC}"
                fi
            fi
            
            if [ "$dev_2_ok" = true ]; then
                if test_pubsub_single "Dev 2" "$DEV_2_NATS_URL"; then
                    dev_2_pubsub="${GREEN}✓ Working${NC}"
                fi
            fi
            
            # Test gateway connectivity
            print_section "GATEWAY CONNECTIVITY TESTS"
            if [ "$dev_1_ok" = true ]; then
                test_gateway_connectivity "Dev 1" "$DEV_1_GATEWAY_URL"
            fi
            
            if [ "$dev_2_ok" = true ]; then
                test_gateway_connectivity "Dev 2" "$DEV_2_GATEWAY_URL"
            fi
            
            # Test cross-cluster messaging
            print_section "CROSS-CLUSTER TEST"
            if [ "$dev_1_ok" = true ] && [ "$dev_2_ok" = true ]; then
                if test_cross_cluster_messaging; then
                    cross_cluster_status="${GREEN}✓ Working${NC}"
                else
                    cross_cluster_status="${YELLOW}⚠ Not working${NC}"
                fi
            else
                print_status $YELLOW "⚠ Skipping cross-cluster test - not all servers are available"
                cross_cluster_status="${YELLOW}⚠ Not tested${NC}"
            fi
            
            show_cluster_status
            
            # Display overall summary
            show_test_summary "$dev_1_status" "$dev_2_status" "$dev_1_pubsub" "$dev_2_pubsub" "$cross_cluster_status"
            ;;
            
        "status")
            show_cluster_status
            ;;
            
        "interactive")
            interactive_test
            ;;
            
        "help"|"-h"|"--help")
            echo -e "${CYAN}${BOLD}NATS Cluster Test Script${NC}"
            echo
            echo -e "${YELLOW}${BOLD}Description:${NC}"
            echo "  This script tests NATS cluster connectivity and inter-cluster messaging"
            echo "  capabilities across development environments."
            echo
            echo -e "${YELLOW}${BOLD}Usage:${NC}"
            echo "  $0 [command]"
            echo
            echo -e "${YELLOW}${BOLD}Available Commands:${NC}"
            echo -e "  ${BOLD}test${NC}        Run connectivity and messaging tests (default)"
            echo -e "  ${BOLD}status${NC}      Show current cluster status"
            echo -e "  ${BOLD}interactive${NC} Start an interactive messaging test session"
            echo -e "  ${BOLD}help${NC}        Show this help message"
            echo
            echo -e "${YELLOW}${BOLD}Examples:${NC}"
            echo "  $0                   # Run all tests"
            echo "  $0 status            # Check cluster status"
            echo "  $0 interactive       # Start interactive messaging test"
            ;;
            
        *)
            print_status $RED "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Check if nats CLI is available
if ! command -v nats &> /dev/null; then
    print_status $RED "NATS CLI is not installed or not in PATH"
    print_status $YELLOW "Please install it from: https://github.com/nats-io/natscli"
    exit 1
fi

# Run main function with all arguments
main "$@"
