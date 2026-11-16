# Loom

Loom 1.2.0 runs as one ARM64 pod at https://loom.leogues.com, using the existing
nginx Gateway and wildcard certificate. The upstream chart is pinned to its release
commit and the image to its multi-platform digest.

## Data and models

Memories, conversations, vectors and Loom's state live in `loom` and
`loom_telemetry` on the existing ClickHouse in `monitoring`; coordination uses its
Keeper. These databases share the existing ClickHouse PVC and its single-node
availability. Their data is not covered by the observability tables' 72-hour TTL.
The pod's 2 GiB cache and 1 GiB scratch directory are ephemeral.

The image includes the local BGE-small embedding model (384 dimensions). No model
API key, hosted model, separate ClickHouse, Postgres, extractor or assistant is
installed. The LLM is the upstream no-provider fallback; LLM-dependent summaries,
answers and automatic fact extraction do not produce useful results in this setup.
Codex can write memories directly and retrieve them through MCP.

The NetworkPolicy admits only the nginx Gateway and permits egress only to DNS,
ClickHouse and the Kubernetes API. Loom cannot call Internet model providers or
external telemetry endpoints. Codex receives any memory it reads through MCP.

## Access

Authentication is required for the API and MCP; public self-signup is off. The
owner account uses `leonardo.rodrigues@nemu.com.br`, with org `leogues` and personal
namespace `leonardo`. OAuth is enabled for MCP clients that support browser login.
Provider credentials and the signing/sealing root are not stored in chart values.

`oracle-infra/infra/envs/prod/k8s/secrets/` owns the SOPS-encrypted Secrets:

- `loom/loom-secrets`: ClickHouse password and `LOOM_JWT_SECRET`.
- `monitoring/loom-clickhouse-auth`: password hash for SQL provisioning.

The bootstrap Job runs before Loom. It gives the service user access only to its
databases and required system tables, and the reader SELECT on `loom.*` with
query limits. The service does not receive the ClickHouse administrator password.
`keeper_map_path_prefix` on ClickHouse enables the KeeperMap tables Loom requires.

## Operations

```bash
kubectl --kubeconfig ~/.kube/k3s-harus -n loom rollout status deploy/loom
kubectl --kubeconfig ~/.kube/k3s-harus -n loom exec deploy/loom -- loom doctor
```

Install the official `loom@loom` Codex plugin and point its MCP entry and
`~/.loom/config.json` at this server. A writer token is sufficient for memory
tools; the owner uses a separate admin account. The plugin's hooks require the
user's approval in an interactive Codex session. MCP tools are independent of
that approval. Never commit tokens or passwords.

Back up both ClickHouse databases, Keeper and `LOOM_JWT_SECRET`. A replacement
root loses access to encrypted credentials; follow the upstream root rotation
procedure. An embedding-model change requires a coordinated publication and
re-embedding, not an ordinary Argo rolling update. Bootstrap uses `IF NOT EXISTS`;
credential rotation must explicitly update both SQL users and the Secret, then
restart Loom. Bump the bootstrap Job name when its SQL changes.

References: [Kubernetes](https://github.com/ClickHouse/loom/blob/v1.2.0/docs/operations/kubernetes.md),
[Codex integration](https://github.com/ClickHouse/loom/blob/v1.2.0/docs/features/integrations/codex.md).
