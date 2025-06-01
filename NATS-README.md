# NATS Cluster Inter-connection Test

This script helps test NATS cluster inter-connection between development and staging environments running on remote Kubernetes clusters.

## Servers
- **Dev**: `nats.dev.dramisinfo.com:4222` (NATS) / `:7222` (Gateway)
- **Staging**: `nats.staging.dramisinfo.com:4222` (NATS) / `:7222` (Gateway)

## Usage

### 1. Test Individual Servers and Connectivity
```bash
./nats-cluster-test.sh test
# or simply
./nats-cluster-test.sh
```

This will:
- Test connectivity to both NATS servers
- Get server information
- Test gateway connectivity
- Test pub/sub on each server individually
- Test cross-cluster messaging (if clusters are connected)

### 2. Check Cluster Status
```bash
./nats-cluster-test.sh status
```

Shows the current status of both servers including cluster and gateway information.

### 3. Interactive Testing
```bash
./nats-cluster-test.sh interactive
```

Starts an interactive session where you can test messaging between servers in real-time.

## Understanding Test Results

- **Server connectivity**: Verifies that NATS servers are running and accessible
- **Gateway connectivity**: Tests if gateway ports are reachable (may show inconclusive for remote clusters)
- **Pub/Sub tests**: Confirms messaging works on individual servers
- **Cross-cluster messaging**: Tests if messages can flow between dev and staging clusters

## Troubleshooting

- **Connection refused**: Check if NATS servers are running and ports are accessible
- **Cross-cluster messages not received**: Clusters may not be connected yet, check your Kubernetes NATS configuration
- **Gateway test inconclusive**: This is normal for remote clusters where direct port access may be restricted
- **Permission denied**: Ensure the script is executable with `chmod +x nats-cluster-test.sh`

## Example Commands

You can test manually with these commands:

```bash
# Subscribe on staging
nats sub --server="nats://nats.staging.dramisinfo.com:4222" "test.subject"

# Publish from dev (in another terminal)
nats pub --server="nats://nats.dev.dramisinfo.com:4222" "test.subject" "Hello from dev!"
```

If clustering is working, the message should appear on the staging subscriber.

## Cluster Setup on Kubernetes

Since your NATS servers are running on Kubernetes clusters, the cluster inter-connection would be configured through:
- Kubernetes services and ingress controllers
- NATS Helm charts or operators with gateway configuration
- Network policies allowing communication between clusters

The script will test the current state without making any configuration changes.
