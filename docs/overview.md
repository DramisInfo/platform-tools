# Overview

`platform-tools` is the GitOps configuration surface for the `platform-core`
Argo CD Application across the DramisInfo platform clusters. It also bundles
the docker-compose NATS cross-cluster load-test stack and a few operator
scripts (`kube.sh`, `nats-cluster-test.sh`, `ansible/playbook.yml`).

The repo is consumed by Argo CD; nothing here is applied by hand.

## What lives here

The repo owns three concerns:

1. **The base `Application`.** `base/platform-core.yaml` is the single source
   of truth for the `platform-core` Argo CD `Application`. It pins the
   `platform-core` chart from
   [DramisInfo/platform-helm](https://github.com/DramisInfo/platform-helm) at
   `targetRevision: HEAD` and applies automated prune + selfHeal with
   `CreateNamespace=true`.
2. **Per-cluster overlays.** `overlays/<cluster>/` is one Kustomize overlay
   per target cluster. Each overlay inherits `../../base` and applies a
   strategic-merge patch on `spec.source.helm.valuesObject` to set
   `global.clusterName`, toggle `bootstrap.hermesSre.enabled` /
   `bootstrap.monitoring.enabled`, configure the NATS gateway block, and (for
   `cace-1-dev`) inject the Crossplane UMI client ID.
3. **The NATS load-test stack.** `nats-load-test/` is a docker-compose stack
   (Fastify `publisher`, NATS `subscriber`, k6 load generator) driven from a
   workstation via `nats-cluster-test.sh`. It publishes on
   `nats.cace-1-dev.dramisinfo.com` and subscribes on
   `nats.cace-2-dev.dramisinfo.com` to verify cross-cluster message delivery
   and latency.

The `kube.sh` and `ansible/playbook.yml` helpers are operator shortcuts: the
first pulls a kubeconfig from a k3s master into `~/.kube/config`, the second
refreshes every Argo CD `Application` across all four k3s masters.

## Clusters currently configured

Four clusters are configured via overlays:

- `overlays/az-1/` — dev, `clusterName: az-1`, NATS gateway points at
  `az-2` (`az-2-cluster`).
- `overlays/az-2/` — dev, mirror of `az-1/` for the second AZ.
- `overlays/cace-1-dev/` — dev, `clusterName: cace-1-dev`, `hermesSre` on,
  monitoring off, gatekeeper `excludedNamespaces` populated, NATS gateway
  **disabled**. Also hosts the `teams/team-alpha/` AppProject + ApplicationSet
  + Namespace bundle and the `patches/crossplane-identity.yaml` patch for the
  public Azure UMI client ID.
- `overlays/cace-2-dev/` — staging, `clusterName: cace-2-dev`, monitoring on,
  NATS gateway points at `cace-1-dev`.

The `cace-2-dev` cluster itself is decommissioned (see commit history from
2026-06-23). The `cace-2-dev/` overlay's `clusterName` and its own gateway
declaration remain valid as long as `cace-2-dev` itself exists, but
`cace-1-dev/patches/platform-core.yaml` must keep
`bootstrap.nats.gateway.enabled: false`.

## Who uses this repo

- **Platform operators** — render overlays with `kustomize build`, refresh
  Argo CD via the ansible play, run the NATS cross-cluster load test, and
  tweak overlay patches when a cluster's configuration needs to change.
- **AI agents** — `AGENTS.md` is the authoritative guide. The `.github/agents/`
  specs (`component-manager`, `dashboard`) and the
  `.github/prompts/manage-component.prompt.md` prompt are scoped to
  `cace-1-dev` only.
- **Anyone reading the rendered output** — the manifests in `overlays/`
  describe exactly what Argo CD will reconcile in each cluster.

## When to touch this repo

Touch this repo when:

- A cluster's `platform-core` configuration needs to change (toggle
  `hermesSre`, `monitoring`, the NATS gateway block, gatekeeper
  `excludedNamespaces`, the Crossplane UMI client ID).
- A new cluster overlay needs to be added.
- The Crossplane UMI client ID for `cace-1-dev` rotates (the `clientId` is a
  public Azure Application ID, not a secret; rotations land via PR).
- The NATS load-test stack needs new scenarios, additional replicas, or
  different defaults.

Do not touch this repo to change the chart itself — that lives in
[DramisInfo/platform-helm](https://github.com/DramisInfo/platform-helm) and
flows through `targetRevision: HEAD` automatically.

## Deploy path

Argo CD is the only deploy path. Each overlay renders to an `Application` CR
that Argo CD reconciles in the target cluster. The `Application` carries
`argocd.argoproj.io/sync-wave: "-100"` so `platform-core` reconciles before
anything that depends on it, and the
`resources-finalizer.argocd.argoproj.io` finalizer so Argo CD can clean up
on delete.

## Layout at a glance

- `base/` — `platform-core` `Application` (chart pin, sync policy, finalizer).
- `overlays/az-1/`, `overlays/az-2/`, `overlays/cace-1-dev/`,
  `overlays/cace-2-dev/` — per-cluster patches.
- `overlays/cace-1-dev/teams/team-alpha/` — AppProject + ApplicationSet +
  Namespace template (standalone kustomization; not yet listed in
  `cace-1-dev/kustomization.yaml`).
- `nats-load-test/` — docker-compose stack.
- `nats-cluster-test.sh` — wrapper around the compose file.
- `kube.sh` — kubeconfig pull.
- `ansible/` — refresh play for Argo CD across all k3s masters.
- `.github/agents/`, `.github/prompts/` — repo-local agent specs (scoped to
  `cace-1-dev`).
- `AGENTS.md` — agent-facing source of truth.
