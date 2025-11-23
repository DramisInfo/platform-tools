# OpenTelemetry GitHub Receiver overlay (cace-1-dev)

This overlay deploys an OpenTelemetry Collector configured to scrape GitHub metrics via a GitHub App authentication extension (githubappauth). It uses a secret to store your GitHub App ID, Installation ID, and private key.

Security: DO NOT commit private keys to git. Use SealedSecrets, ExternalSecrets or HashiCorp Vault for production.

What to do before applying:
1. Create a GitHub App (See `Guidance` in the project root readme or the instructions below). Copy the `App ID`, `installation ID`, and download the `private key (pem)`.
2. Create the K8s secret with your values (use the `create-secret.sh` script below or use your secret management solution). The overlay deploys the collector into the `monitoring` namespace to match your existing secret.
3. Update `collector-config.yaml` if you need a different `github_org` or search query.

Create the secret (example):
```bash
kubectl -n observability create secret generic github-app-secret \
  --from-literal=github_app_id="2340884" \
  --from-literal=github_installation_id="96193865" \
  --from-file=github_private_key_pem=./private-key.pem \
  --from-literal=github_webhook_secret="your-webhook-secret"
```

Or use the included `create-secret.sh` script for a quick local secret creation.

Deploy the overlay:
- Commit your changes to the repo and let ArgoCD sync the `overlays/cace-1-dev` overlay to the cluster (recommended in your setup).
- (Optional) For dev/test, apply locally (not recommended for production):
```bash
kubectl apply -k overlays/cace-1-dev
```

ArgoCD notes:
- Push your changes to `main` and let ArgoCD sync; ensure your ArgoCD app points at this repo & overlay path.
- Make sure `github-app-secret` exists in the `monitoring` namespace before ArgoCD attempts to sync. If you're using ExternalSecrets or other tooling, ensure the secret is available to ArgoCD.

Verify:
- Collector pod is running and logs show successful auth.
- Prometheus picks up the collector metrics via the `ServiceMonitor`.
- Grafana shows the `vcs.*` metrics on the DORA dashboard.

Useful validation commands:

```bash
# check pods
kubectl -n monitoring get pods -l app=otel-github-collector

# check logs for auth success
kubectl -n monitoring logs deploy/otel-github-collector -c otel-collector | tail -n 200

# verify the service is visible
kubectl -n monitoring get svc otel-github-collector

# port-forward and check metrics locally
kubectl -n monitoring port-forward svc/otel-github-collector 8888:8888 &
curl http://127.0.0.1:8888/metrics | head -n 50
```

If Prometheus is operator-managed and `ServiceMonitor` is configured properly you should see the target under `Status -> Targets` in Prometheus UI (or query the Prometheus `targets` API).

