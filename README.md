# oracle-gitops

GitOps source-of-truth for the Oracle Cloud K3s cluster, reconciled by Argo
CD running in [`leogues/oracle-infra`](https://github.com/leogues/oracle-infra).

This repo is the **only** place to change anything inside the cluster after
the cluster is up. `oracle-infra` is responsible for the cloud
infrastructure plus the Argo CD bootstrap; everything else lives here.

## Layout

```
platform/         # cluster platform stacks (CRDs, storage, networking, data, observability, gitops tooling)
default/          # generic Helm chart used by every application under envs/
envs/
  production/     # production applications — picked up by the environments-appset
```

### `platform/`

Cluster platform deployments organised as a **2-layer app-of-apps**. The
root Application — defined in `oracle-infra/infra/envs/prod/k8s/helm/stacks/argocd/resources/platform-root.yaml` — points at `platform/_groups/`,
which holds six wrapper Applications (`crds`, `foundation`, `networking`,
`data`, `observability`, `gitops`). Each wrapper recursively syncs its
`platform/<category>/` directory.

Sync waves on the wrappers control the order in which categories come up.
Leaf Applications inside each category use sync-wave annotations only for
intra-group ordering (e.g. `cnpg-cluster` after `cnpg-operator`).

See [`platform/README.md`](platform/README.md) for the full convention.

### `envs/production/`

User-facing application Applications. Each subdirectory holds:

- `application.yaml` — Argo Application using the `default/` chart with
  multi-source `$values`, plus image-updater annotations for tag bumps.
- `values.yaml` — application-specific values consumed by `default/`.

A single `ApplicationSet` (defined in `oracle-infra` alongside Argo CD)
generates one parent Application per env that discovers everything under
`envs/<env>/`.

### `default/`

Generic Helm chart shared by every application under `envs/`. Provides the
standard set of resources (Deployment, Service, HPA, HTTPRoute,
ServiceAccount) with sane defaults. Per-app overrides live in the
application's `values.yaml`.
