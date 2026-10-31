# Observability

Argo CD manages one ClickHouse (26.10.2.103), one Keeper of the same version,
the official ClickHouse operator (0.0.8), OTel Collector Contrib (0.163.2,
chart 0.178.1), and Grafana (chart 14.2.0) in `monitoring`.
The wrapper explicitly selects these Applications. Loki, Mimir and the old
k8s-monitoring chart are preserved but disabled.

## Data flow

- OTLP metrics and host/kubelet metrics → Collector → Prometheus remote write
  → ClickHouse `prometheus.metrics` (`TimeSeries`) → Grafana Prometheus datasource.
- OTLP logs/traces and non-production container logs → Collector → ClickHouse
  exporter → `otel.otel_logs` / `otel.otel_traces` → Grafana ClickHouse datasource.
- Prometheus scraping discovers infrastructure endpoints outside `production`,
  including PostgreSQL, operators, Argo CD, DNS, Gateway, Longhorn and the
  observability stack. Production pod targets are dropped before scraping.
- Container file logs exclude `production` and the Collector itself (to prevent
  an export-error feedback loop). OTLP remains available to production clients.
- No instrumentation, images, or application environment changes are included.

The cluster-internal OTLP endpoints are
`otel-collector.monitoring.svc.cluster.local:4317` (gRPC) and
`http://otel-collector.monitoring.svc.cluster.local:4318` (HTTP). They are not
published through the Gateway. Applications can push all signals later;
the metrics pipeline converts delta metrics to cumulative before remote write.
Native OTLP and scraped metrics use separate remote-write exporters. The
scraped pipeline preserves original Prometheus metric names for the official
PostgreSQL dashboard. Kubelet/cAdvisor scrapes also drop samples labeled
`namespace="production"`. Existing kubelet stats continue to provide pod
resource usage across the cluster.

## Grafana

URL: https://grafana.leogues.com. Credentials reuse `monitoring/grafana-admin`,
managed by SOPS/Terraform in `oracle-infra`. ClickHouse reader/writer/bootstrap
credentials are in the separately encrypted `monitoring/clickhouse-auth` Secret.
The Grafana account has SELECT grants on telemetry/schema metadata and can
create temporary tables required by PromQL evaluation. It cannot change
persistent telemetry tables. The Collector has write/schema permissions only
for telemetry.

The official ClickHouse plugin is pinned to 4.23.4. Three upstream OTel
dashboards are provisioned from that plugin version: Logs Explorer, Traces
Explorer and Service Dashboard. Their source is
https://github.com/grafana/clickhouse-datasource/tree/v4.23.4/src/dashboards.
The additional `Harus — Infraestrutura` dashboard uses PromQL for node CPU,
memory, root filesystem, active series, and CPU/memory per pod.
No traces from applications should be expected until they are instrumented.

The official **CloudNativePG** dashboard comes from the `cluster` chart 0.0.5
in https://github.com/cloudnative-pg/grafana-dashboards. Only datasource and
initial variable selections are configured locally; its queries stay upstream.
`kube-state-metrics` chart 8.8.0 supplies a small allowlist of pod/node metadata.
Grafana provisions the required CPU recording rule and writes its output to
ClickHouse using the existing writer credential through a dedicated target
datasource. There are no alert rules or notifications.

Dashboard manifests include `dashboard` in their filenames. PostgreSQL panels
for replicas, backups, WAL PVCs and resource-request ratios can be empty when
those features or requests are not configured on the single-instance database.

## Storage, bootstrap and upgrades

Longhorn PVC requests: ClickHouse 20 GiB, Keeper 1 GiB, Grafana 1 GiB,
with one Longhorn replica. This is a single-node deployment with no failover.
ClickHouse has a 4 GiB container memory limit and 3 GiB server memory budget.
Collector file checkpoints and export queue use persistent node directories.

`clickhouse-bootstrap-v2` is an idempotent GitOps Job. It creates databases,
the TimeSeries table and separate SQL users. The Collector creates its standard
log/trace tables. Metric samples, logs and traces have a 72-hour TTL; TimeSeries
series/tag metadata is separate and is not deleted by the samples TTL. The
extra recent-sample copy is disabled to avoid duplicating samples on this node.

TimeSeries/PromQL is an opt-in preview. Its sample schema and HTTP API are tied
to the pinned ClickHouse version. Do not use DDL from current documentation
without comparing it to 26.10. Schema upgrades require a reviewed migration;
changing the bootstrap ConfigMap alone does not rerun an already completed Job.
Bump its Job name when a new migration is necessary. Secret rotation must also
update existing SQL users, since bootstrap uses `CREATE USER IF NOT EXISTS`.

Deployment validation on 2026-10-31 covered synthetic OTLP metrics, logs and
traces, their storage in ClickHouse, Grafana datasource health, PromQL panel
queries and a SQL query through Grafana. Production pod templates, replica
counts and images were compared before/after and were unchanged. The Collector
waits for the bootstrap user before starting. A subsequent scope update adds
non-production logs and `/metrics` discovery, while retaining production pod
template/image/replica settings. Default overrides were removed only from the
new observability values, with identical Helm output before/after cleanup.

References:

- https://clickhouse.com/docs/products/kubernetes-operator/install/helm
- https://clickhouse.com/docs/concepts/features/interfaces/prometheus
- https://clickhouse.com/blog/introducing-promql
- https://opentelemetry.io/docs/platforms/kubernetes/helm/collector/
