# platform-tools — GitOps overlays for the DramisInfo platform clusters

## What this repo is

GitOps configuration for the `platform-core` Argo CD Application, expressed as Kustomize
overlays per cluster. It also bundles a docker-compose NATS cross-cluster load-test stack
(`nats-load-test/`) and a couple of operator scripts (`kube.sh`, `nats-cluster-test.sh`,
`ansible/playbook.yml`). Single remote: `https://github.com/DramisInfo/platform-tools.git`,
default branch `main`.

## Layout

- `base/` — single source of truth for the `platform-core` Argo CD `Application`. Pulls
  `platform-core` from `DramisInfo/platform-helm` (chart path `platform-core`, rev `HEAD`)
  with `CreateNamespace=true`, automated prune + selfHeal. Kustomize `commonLabels` are
  added by each overlay, not here.
- `overlays/` — one kustomize overlay per target cluster. Each inherits `../../base` and
  applies a `patches/platform-core.yaml` strategic-merge patch on the
  `Application.spec.source.helm.valuesObject`. Currently:
  - `az-1/` — dev, NATS gateway to `az-2` (cluster name `az-1-cluster`).
  - `az-2/` — dev, mirror of `az-1/` for the second AZ.
  - `cace-1-dev/` — dev, `clusterName: cace-1-dev`, hermesSRE on, monitoring off, gatekeeper
    excluded-namespaces list, NATS gateway disabled (cace-2-dev no longer exists; see the
    2026-06-23 commit). Also hosts `teams/team-alpha/` (AppProject + ApplicationSet +
    Namespace template — its own `kustomization.yaml` is a standalone entry point, not
    yet listed under `cace-1-dev/kustomization.yaml`'s `resources:`) and a
    `patches/crossplane-identity.yaml` for the Crossplane UMI client ID.
  - `cace-2-dev/` — staging, `clusterName: cace-2-dev`, monitoring on, NATS gateway to
    cace-1-dev.
- `nats-load-test/` — docker-compose stack: `publisher` (Fastify → NATS on
  `nats.cace-1-dev.dramisinfo.com:4222`), `subscriber` (NATS on
  `nats.cace-2-dev.dramisinfo.com:4222`), `k6` load generator. NOT deployed via ArgoCD.
- `nats-cluster-test.sh` — wrapper around `nats-load-test/docker-compose.yml` with
  `build | test | status | interactive | down`. Env overrides: `VUS`, `DURATION`,
  `PUBLISHER_REPLICAS`, `SUBSCRIBER_REPLICAS`.
- `kube.sh` — one-shot helper to scp the kubeconfig from `192.168.20.10` (k3s master) and
  merge it as context `k3s-dev1` into `~/.kube/config`.
- `ansible/` — `inventory.ini` lists the four k3s masters (`192.168.20.10`, `.20`, `.30`,
  `.90`); `playbook.yml` refreshes every Argo CD `Application` via `kubectl patch`.
- `.github/agents/` — repo-local Copilot-style agent specs (`component-manager`,
  `dashboard`). Both are scoped to `cace-1-dev` only (see guardrails).
- `.github/prompts/` — `manage-component.prompt.md` wires the `component-manager` agent.

## Conventions

- **Language / formats.** YAML (kustomize, Argo CD CRDs, ansible), Bash, Node 22 ESM
  (`publisher/`, `subscriber/`), and k6 JS (`k6/script.js`). No package manager at repo
  root — subprojects each ship their own `package.json` / `Dockerfile`.
- **Build / run.**
  - NATS load test: `./nats-cluster-test.sh help` then `test` (or `interactive`).
  - Manual: `docker compose -f nats-load-test/docker-compose.yml up --build`.
  - Kustomize render: `kustomize build overlays/<env>`.
  - ArgoCD refresh across all clusters:
    `ansible-playbook -i ansible/inventory.ini ansible/playbook.yml` (uses
    `/etc/rancher/k3s/k3s.yaml` on the target).
  - Pull a kubeconfig: `./kube.sh` (hard-coded to `192.168.20.10`).
- **No CI workflows, no lint config, no test framework at the repo root** — there is
  nothing to run. Do not invent one.
- **Commits.** Conventional Commits style observed in history: `feat(cace-1-dev): ...`,
  `fix(nats): ...`, `Update Crossplane UMI client ID ...`. Recent history is dominated by
  automated client-ID rotation commits.
- **PRs.** Merges go through PRs (e.g. #3 `feat/enable-hermes-sre` → `main`). Branch
  naming follows `<type>/<scope>` (e.g. `feat/enable-hermes-sre`).
- **Patches.** All overlay patches target `kind: Application, name: platform-core` and
  only override `spec.source.helm.valuesObject` (+ occasional `syncPolicy`).

## GitOps / deployment context

- Argo CD is the only deploy path. The repo is consumed by an Argo CD instance that
  already has the `argocd` namespace and a project named `default`. The `Application`
  is installed with `sync-wave: "-100"` and `resources-finalizer.argocd.argoproj.io`.
- Cluster hostnames referenced by the overlays / load test:
  `nats.az-1.dramisinfo.com`, `nats.az-2.dramisinfo.com`,
  `nats.cace-1-dev.dramisinfo.com`, `nats.cace-2-dev.dramisinfo.com`,
  `grafana.cace-1-dev.dramisinfo.com`. cace-2-dev is **gone** — do not re-enable that
  gateway.
- `cace-1-dev/teams/team-alpha/appset.yaml` is an ApplicationSet that scans
  `app-teams/team-alpha/cace-1-dev/*` in this same repo. That path does not exist yet
  (no `app-teams/` directory in the tree); the generator currently produces nothing.
- The `cace-1-dev` Crossplane UMI client ID is a public Azure Application (client) ID,
  not a secret — it is safe to commit and is rotated via PR.

## What NOT to do

- **Do not edit `base/platform-core.yaml` chart version lightly.** Every overlay inherits
  it; changes ship to all four clusters at once. Prefer a targeted overlay patch.
- **Do not modify overlays other than `cace-1-dev`.** The
  `.github/agents/component-manager.agent.md` and `dashboard.agent.md` agents are
  explicitly scoped to `cace-1-dev`; treat the other overlays as read-only from this
  repo's agent perspective.
- **Do not bypass ArgoCD** by `kubectl apply`-ing resources from a workstation. Use the
  `ansible/playbook.yml` refresh or the ArgoCD UI/API.
- **Do not re-enable the cace-2-dev NATS gateway.** The cluster was decommissioned on
  2026-06-23 and the gateway was blocking JetStream metadata RAFT leader election.
  `cace-2-dev` is referenced as a peer only by the `cace-2-dev/` overlay itself; that
  overlay's `clusterName` and its own gateway declaration are still valid, but the
  `cace-1-dev` patch must keep `gateway.enabled: false`.
- **Do not commit real secrets** (kubeconfigs, kubeconfig certs, ArgoCD admin passwords,
  registry creds, etc.). The committed `clientId` in `crossplane-identity.yaml` is a
  public Azure UMI client ID, not a secret — do not paste the matching secret value here.
- **Do not move `nats-load-test/` under ArgoCD.** It is intentionally a docker-compose
  stack driven from a workstation; it talks to the clusters over the public NATS
  hostname, not via in-cluster service discovery.
- **Do not change `targetRevision: "HEAD"`** on the upstream `DramisInfo/platform-helm`
  Application without checking that every overlay still renders. The `HEAD` pin is
  deliberate.
- **Do not add a `dependencies:` block to `package.json` at the repo root** — there is
  no top-level Node project. `publisher/` and `subscriber/` are independent.

## Related repos

- `DramisInfo/platform-helm` — source of the `platform-core` Helm chart consumed by
  `base/platform-core.yaml` (`path: platform-core`, `targetRevision: HEAD`).

## Pointers

Files consulted to write this document:

- `base/kustomization.yaml`, `base/platform-core.yaml`
- `overlays/az-1/kustomization.yaml`, `overlays/az-1/patches/platform-core.yaml`
- `overlays/az-2/kustomization.yaml`, `overlays/az-2/patches/platform-core.yaml`
- `overlays/cace-1-dev/kustomization.yaml`, `overlays/cace-1-dev/patches/platform-core.yaml`,
  `overlays/cace-1-dev/patches/crossplane-identity.yaml`
- `overlays/cace-1-dev/teams/team-alpha/{kustomization,appset,app-project,namespaces}.yaml`
- `overlays/cace-2-dev/kustomization.yaml`, `overlays/cace-2-dev/patches/platform-core.yaml`
- `nats-load-test/docker-compose.yml`, `nats-load-test/publisher/{Dockerfile,index.js,package.json}`,
  `nats-load-test/subscriber/{Dockerfile,index.js,package.json}`,
  `nats-load-test/k6/{Dockerfile,script.js}`
- `nats-cluster-test.sh`
- `kube.sh`
- `ansible/inventory.ini`, `ansible/playbook.yml`
- `.github/agents/component-manager.agent.md`, `.github/agents/dashboard.agent.md`
- `.github/prompts/manage-component.prompt.md`
- `git log --oneline -20` on `main` (commit style, PR #3, cace-2-dev removal)
