# docs

User guide and architecture documentation for `DramisInfo/platform-tools`.

This bundle is the human-facing companion to `AGENTS.md`. `AGENTS.md` is the
source of truth for AI agents working in this repo; the files here explain
what the repo is, how the pieces fit together, and how to do day-to-day work
in it.

## How to navigate

- [overview.md](./overview.md) — what this repo is, who uses it, when to touch it.
- [architecture.md](./architecture.md) — how the base, overlays, Argo CD, and
  the NATS load-test stack fit together.
- [user-guide.md](./user-guide.md) — day-to-day tasks: rendering overlays,
  running the NATS load test, refreshing Argo CD, troubleshooting.
- [related-repos.md](./related-repos.md) — pointers to sibling repos in the
  DramisInfo platform stack.

If you are an AI agent, read `AGENTS.md` first — it has the layout, the
conventions, and the "what NOT to do" guardrails. The `docs/` files here are
written for humans operating the repo.

## Scope of these docs

The `docs/` folder is a documentation-only addition. It does not change any
manifests, scripts, charts, or workflows in the repo. All of the things
described here were already true of the repo before this folder existed; the
docs just describe them.

## What this repo is not

- It is not the Helm chart. The chart lives in
  [DramisInfo/platform-helm](https://github.com/DramisInfo/platform-helm) and
  is consumed by the `Application` defined in `base/`.
- It is not the Crossplane compositions. Those live in
  [DramisInfo/platform-crossplane-compositions](https://github.com/DramisInfo/platform-crossplane-compositions).
- It is not the platform bootstrap for new clusters. The cluster topology and
  bootstrap process are documented in
  [DramisInfo/home-lab](https://github.com/DramisInfo/home-lab).

See [related-repos.md](./related-repos.md) for the full list.
