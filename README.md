# oracle-gitops

GitOps source-of-truth for the Oracle Cloud K3s cluster, consumed by Argo CD running in [`leogues/oracle-infra`](https://github.com/leogues/oracle-infra).

## Layout

```
envs/
  prod/   # production applications (synced by environments-appset)
```

Applications under `envs/prod/` are picked up recursively by the Argo CD `ApplicationSet` defined in `oracle-infra` (`infra/envs/prod/k8s/helm/stacks/argocd/resources/applicationset.yaml`).
