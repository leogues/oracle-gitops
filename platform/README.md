# platform/

Cluster platform stacks reconciled by Argo CD. Pattern: **2-layer app-of-apps**.

```
platform/
├── _groups/        # 5 active wrappers; observability wrapper commented out
└── <category>/<stack>/{application.yaml,values.yaml,extras/}   # leaf apps
```

## Layers

1. **Root** (`cluster/root-platform.yaml`) — points at `platform/_groups/`, creates 5 active wrapper Applications.
2. **Group wrappers** (`platform/_groups/*.yaml`) — each points at its `platform/<category>/` directory. Sync-wave on the wrapper controls category order.
3. **Leaf apps** (`platform/<category>/<stack>/application.yaml`) — actual chart deployments. Sync-wave optional, only for intra-group ordering (e.g. `cnpg-cluster` after `cnpg-operator`).

## Group wave assignment

| Wave | Category        | Why first/last                                         |
| ---- | --------------- | ------------------------------------------------------ |
| 0    | crds            | CRDs must exist before any controller using them       |
| 10   | foundation      | Storage (Longhorn) — PVCs everywhere depend on it      |
| 20   | networking      | Gateways + TLS + DNS — needed by HTTPRoutes downstream |
| 30   | data            | Operators + their managed clusters                     |
| 40   | observability (disabled) | Wrapper commented out; configuration preserved |
| 50   | gitops          | Argo CD tooling (image-updater) — last, depends on rest |

Gaps of 10 leave room for new categories (e.g. `25-security/`) without renumbering.

## Adding a new stack

```
platform/<category>/<new-stack>/
├── application.yaml      # Argo Application, multi-source (chart + $values)
├── values.yaml           # chart values
└── extras/               # optional — extra k8s manifests beyond the chart
    ├── application.yaml  # separate Application for prune granularity
    └── <whatever>.yaml
```

Wrapper for `<category>` discovers it automatically (path recurse). No edit anywhere else.

## Health-aware ordering

Argo CD waits for each wave to be Healthy before the next. Wrappers have built-in `Application` health check (Synced + all children Healthy). Cascade works without extra config.

If a CRD or chart lacks a built-in health check (e.g. Longhorn `Volume`, CNPG `Cluster`), Argo CD ships custom Lua scripts for many — see https://github.com/argoproj/argo-cd/tree/master/resource_customizations. Add new ones via `argocd-cm` ConfigMap if missing.
