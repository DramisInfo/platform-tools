# User guide

Day-to-day tasks for working with this repo: rendering overlays, applying
changes, running the NATS load test, refreshing Argo CD, and troubleshooting
the common failure modes.

## Prerequisites

- `kubectl`
- `kustomize`
- `docker` (with Compose v2: `docker compose ...`)
- `ansible` — only if you want to use the cluster refresh play
- `gh` — only for opening PRs

Argo CD must already be installed in each target cluster, with a project
named `default` and the `argocd` namespace present. Cluster bootstrap is out
of scope for this repo; it is owned by
[DramisInfo/home-lab](https://github.com/DramisInfo/home-lab).

SSH access to `ubuntu@192.168.20.10` (or whichever k3s master you target)
is required for `kube.sh` and the ansible play.

## Render an overlay

To verify a patch lands cleanly, render the overlay with `kustomize` and
inspect the output:

```bash
kustomize build overlays/cace-1-dev | less
```

Re-render `base/` first if a base change is suspected — every overlay
inherits it, so a chart-pinned diff in `base/platform-core.yaml` will surface
in all four overlays.

## Tweak an overlay patch

The values you actually touch live in `overlays/<env>/patches/`, not in any
Helm values file. Open the patch and edit the `valuesObject` block:

- `overlays/<env>/patches/platform-core.yaml` — strategic-merge patch on
  `spec.source.helm.valuesObject`. Sets `global.clusterName`, toggles
  `bootstrap.hermesSre.enabled` / `bootstrap.monitoring.enabled`, and
  configures the `bootstrap.nats.gateway` block (advertise URL, peer
  gateways, enabled flag).
- `overlays/cace-1-dev/patches/crossplane-identity.yaml` — public Azure UMI
  `clientId` for the Crossplane identity. Safe to commit; rotated via PR by
  an automated job.

Then re-render with `kustomize build overlays/<env>` to verify the change.

## Run the NATS cross-cluster load test

The wrapper auto-builds images on first run, then drives the publisher /
subscriber / k6 stack end-to-end:

```bash
./nats-cluster-test.sh test
# 10 VUs for 60s, 10 publisher + 10 subscriber replicas by default
```

Override defaults with environment variables:

```bash
VUS=50 DURATION=120s \
  PUBLISHER_REPLICAS=3 SUBSCRIBER_REPLICAS=2 \
  ./nats-cluster-test.sh test
```

Other subcommands:

- `./nats-cluster-test.sh build` — build (or rebuild) images.
- `./nats-cluster-test.sh status` — show running containers + publisher
  health.
- `./nats-cluster-test.sh interactive` — start publisher/subscriber in the
  background, tail subscriber logs, print the in-container `wget` command
  for a one-off publish.
- `./nats-cluster-test.sh down` — stop and remove all containers.
- `./nats-cluster-test.sh help` — full usage.

For manual probing without the wrapper, drive the compose file directly:

```bash
docker compose -f nats-load-test/docker-compose.yml up --build
```

## Refresh every Argo CD Application across all clusters

The ansible play iterates over every `Application` in the `argocd`
namespace on each k3s master and patches it with a normal refresh
operation:

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml
```

It uses `KUBECONFIG: /etc/rancher/k3s/k3s.yaml` on the target. The
inventory lists the four masters at `192.168.20.10`, `.20`, `.30`, `.90`.

Use this when an Application shows `OutOfSync` with no diff, or after a
change has landed in the chart but Argo CD has not picked it up.

## Pull a kubeconfig

To pull the dev1 kubeconfig from the k3s master into `~/.kube/config` as
context `k3s-dev1`:

```bash
./kube.sh
```

The script is hard-coded to `ubuntu@192.168.20.10`. Make sure your SSH
agent has the matching key and the host is reachable.

## Open a PR

There is no CI workflow in this repo — branch + PR is the entire review
loop. The repo follows Conventional Commits and `<type>/<scope>` branch
names (e.g. `feat/cace-1-dev/<slug>`, `fix/nats/<slug>`). Automated
client-ID rotations land via PR with the `Update Crossplane UMI client ID
...` prefix.

## Troubleshooting

### `kustomize build` fails on an overlay after a base change

Re-render `kustomize build base` first. Every overlay inherits the base, so
a chart-pinned diff in `base/platform-core.yaml` will surface in all four
overlays. Fix the base (or the offending overlay's patch) and re-render.

### Argo CD shows `platform-core` as `OutOfSync` with no diff

Force a refresh across all clusters via the ansible play
(`ansible-playbook -i ansible/inventory.ini ansible/playbook.yml`). The play
patches every `Application` with a normal refresh operation.

### NATS load test never reaches the healthy publisher count

Check `./nats-cluster-test.sh status` and inspect container logs. A stale
image is the usual cause — run `./nats-cluster-test.sh build` and retry.

### JetStream warnings about "no metadata leader"

Confirm the cace-2-dev gateway is **not** re-enabled in
`overlays/cace-1-dev/patches/platform-core.yaml` —
`bootstrap.nats.gateway.enabled: false`. The `cace-2-dev` cluster was
decommissioned on 2026-06-23 and the gateway was blocking JetStream metadata
RAFT leader election.

### `kube.sh` fails on `scp`

The script is hard-coded to `ubuntu@192.168.20.10`. Make sure your SSH agent
has the matching key and the host is reachable before re-running.

### `team-alpha` ApplicationSet renders zero Applications

This is expected until `app-teams/team-alpha/cace-1-dev/*` exists in the
repo. The ApplicationSet's `git` generator scans that path; with no
directories present, no Applications are produced.

## Security

- Do not commit kubeconfigs, kubeconfig certificates, Argo CD admin
  passwords, or registry credentials.
- The `clientId` in `overlays/cace-1-dev/patches/crossplane-identity.yaml`
  is a public Azure UMI Application (client) ID, not a secret. Do not paste
  the matching secret value into this repo.
- Do not bypass Argo CD with `kubectl apply` from a workstation. Use
  `ansible/playbook.yml` or the Argo CD UI/API.
- Do not move `nats-load-test/` under Argo CD. It is a workstation-driven
  docker-compose stack talking to the clusters over the public NATS
  hostnames.

The full guardrail list — chart-version bumps, overlay scope, the
`targetRevision: HEAD` pin, the absence of a repo-root `package.json`, and
so on — lives in the "What NOT to do" section of
[`AGENTS.md`](../AGENTS.md).
