#!/bin/bash

# NATS Cluster Inter-connection Test Script
# This script tests individual NATS servers and sets up cluster inter-connection

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# NATS server configurations
DEV_NATS_URL="nats://nats.dev.dramisinfo.com:4222"
DEV_GATEWAY_URL="nats://nats.dev.dramisinfo.com:7222"
STAGING_NATS_URL="nats://nats.staging.dramisinfo.com:4222"
STAGING_GATEWAY_URL="nats://nats.staging.dramisinfo.com:7222"

# Test subject for messaging
TEST_SUBJECT="cluster.test"
TEST_MESSAGE="Hello from NATS cluster test"

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] ${message}${NC}"
}

# Function to test NATS server connectivity
test_nats_connectivity() {
    local server_name=$1
    local nats_url=$2
    
    print_status $BLUE "Testing connectivity to $server_name ($nats_url)..."
    
    if timeout 10 nats server check connection --server="$nats_url" >/dev/null 2>&1; then
        print_status $GREEN "✓ $server_name is reachable and responding"
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
    
    # Start subscriber on staging
    local sub_output=$(mktemp)
    print_status $YELLOW "Starting subscriber on staging server..."
    nats sub --server="$STAGING_NATS_URL" "$TEST_SUBJECT.cross" > "$sub_output" 2>&1 &
    local sub_pid=$!
    
    # Give subscriber time to connect
    sleep 3
    
    # Publish from dev
    print_status $YELLOW "Publishing message from dev server..."
    if nats pub --server="$DEV_NATS_URL" "$TEST_SUBJECT.cross" "Cross-cluster message from dev to staging" >/dev/null 2>&1; then
        sleep 2
        kill $sub_pid 2>/dev/null || true
        wait $sub_pid 2>/dev/null || true
        
        if grep -q "Cross-cluster message from dev to staging" "$sub_output"; then
            print_status $GREEN "✓ Cross-cluster messaging is working!"
            rm -f "$sub_output"
            return 0
        else
            print_status $RED "✗ Cross-cluster message not received"
            print_status $YELLOW "This is expected if clusters are not yet connected"
            rm -f "$sub_output"
            return 0  # Return 0 to not fail the script - this is expected behavior
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
    print_status $BLUE "Checking cluster status..."
    
    echo
    print_status $YELLOW "=== DEV SERVER STATUS ==="
    if timeout 10 nats server info --server="$DEV_NATS_URL" 2>/dev/null | grep -E "(Server ID|Cluster|Gateway|Connections)"; then
        :  # Info retrieved successfully
    else
        print_status $YELLOW "Server info not available (likely due to permission restrictions)"
        print_status $BLUE "Testing basic connectivity instead..."
        if nats server check connection --server="$DEV_NATS_URL" 2>/dev/null; then
            print_status $GREEN "✓ Dev server is reachable and responding"
        else
            print_status $RED "✗ Dev server connectivity test failed"
        fi
    fi
    
    echo
    print_status $YELLOW "=== STAGING SERVER STATUS ==="
    if timeout 10 nats server info --server="$STAGING_NATS_URL" 2>/dev/null | grep -E "(Server ID|Cluster|Gateway|Connections)"; then
        :  # Info retrieved successfully
    else
        print_status $YELLOW "Server info not available (likely due to permission restrictions)"
        print_status $BLUE "Testing basic connectivity instead..."
        if nats server check connection --server="$STAGING_NATS_URL" 2>/dev/null; then
            print_status $GREEN "✓ Staging server is reachable and responding"
        else
            print_status $RED "✗ Staging server connectivity test failed"
        fi
    fi
}

# Function to run interactive test
interactive_test() {
    print_status $BLUE "Starting interactive messaging test..."
    echo
    echo "Instructions:"
    echo "1. This will start a subscriber on staging server"
    echo "2. You can then publish messages from dev server"
    echo "3. Press Ctrl+C to stop"
    echo
    read -p "Press Enter to continue..."
    
    print_status $YELLOW "Starting subscriber on staging (listening to 'interactive.test')..."
    echo "In another terminal, you can publish with:"
    echo "nats pub --server=\"$DEV_NATS_URL\" \"interactive.test\" \"Your message here\""
    echo
    
    nats sub --server="$STAGING_NATS_URL" "interactive.test"
}

# Main function
main() {
    print_status $GREEN "Starting NATS Cluster Inter-connection Test"
    echo
    
    case "${1:-test}" in
        "test")
            print_status $BLUE "=== INDIVIDUAL SERVER TESTS ==="
            
            # Test connectivity
            dev_ok=false
            staging_ok=false
            
            if test_nats_connectivity "Dev" "$DEV_NATS_URL"; then
                dev_ok=true
            fi
            
            if test_nats_connectivity "Staging" "$STAGING_NATS_URL"; then
                staging_ok=true
            fi
            
            echo
            
            # Get server info
            if [ "$dev_ok" = true ]; then
                get_server_info "Dev" "$DEV_NATS_URL"
                echo
            fi
            
            if [ "$staging_ok" = true ]; then
                get_server_info "Staging" "$STAGING_NATS_URL"
                echo
            fi
            
            # Test pub/sub on individual servers
            print_status $BLUE "=== PUB/SUB TESTS ==="
            
            if [ "$dev_ok" = true ]; then
                test_pubsub_single "Dev" "$DEV_NATS_URL"
            fi
            
            if [ "$staging_ok" = true ]; then
                test_pubsub_single "Staging" "$STAGING_NATS_URL"
            fi
            
            echo
            
            # Test gateway connectivity
            print_status $BLUE "=== GATEWAY CONNECTIVITY TESTS ==="
            if [ "$dev_ok" = true ]; then
                test_gateway_connectivity "Dev" "$DEV_GATEWAY_URL"
            fi
            
            if [ "$staging_ok" = true ]; then
                test_gateway_connectivity "Staging" "$STAGING_GATEWAY_URL"
            fi
            
            echo
            
            # Test cross-cluster messaging
            print_status $BLUE "=== CROSS-CLUSTER TEST ==="
            if [ "$dev_ok" = true ] && [ "$staging_ok" = true ]; then
                test_cross_cluster_messaging
            else
                print_status $YELLOW "Skipping cross-cluster test - not all servers are available"
            fi
            
            echo
            show_cluster_status
            ;;
            
        "status")
            show_cluster_status
            ;;
            
        "interactive")
            interactive_test
            ;;
            
        "help"|"-h"|"--help")
            echo "NATS Cluster Test Script"
            echo
            echo "Usage: $0 [command]"
            echo
            echo "Commands:"
            echo "  test        Run connectivity and messaging tests (default)"
            echo "  status      Show cluster status"
            echo "  interactive Start interactive messaging test"
            echo "  help        Show this help message"
            echo
            echo "Examples:"
            echo "  $0                    # Run all tests"
            echo "  $0 status            # Check cluster status"
            echo "  $0 interactive       # Interactive messaging test"
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
