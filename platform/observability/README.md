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
The Grafana account has `SELECT, SHOW ON *.*` and `REMOTE ON *.*`, matching
the reader grants in Nemu's ClickHouse installation. This covers system logs,
table metadata and distributed queries used by the cloned dashboards. It can
also create temporary tables required by PromQL evaluation; persistent writes
are not granted. The Collector has write/schema permissions only for telemetry.

The official ClickHouse plugin is pinned to 4.23.4. Logs/traces use its
`latest` OTel schema selector (the UI label is “auto (latest)”).

Dashboards and folders are managed by Grafana Git Sync from the `main` branch
of `leogues/oracle-gitops`, path `grafana-dashboards/`. The PostgreSQL dashboard
is `cloudnativepg.json` (UID `ddg2w79lsgd98gb`). The `clickhouse/` directory has
stable folder metadata and six dashboards: Overview, Advanced Monitoring,
Cluster Analysis, Data Analysis, Query Analysis and Keeper. Overview replaces
the former operator dashboard with 16 panels using native ClickHouse, cAdvisor
and Longhorn metrics. It has no dependency on the Altinity exporter.

ClickHouse dashboards discover cluster names from `system.clusters` and offer
instance, database, table, user, status and query-kind filters where relevant.
No Nemu cluster or database name is selected by default. Keeper namespace/pod
filters discover the available metrics; rate windows use `$__rate_interval`
for the 60-second scrape interval, and outstanding requests is a gauge.
Validation covered all 97 panel queries and 10 query variables with All and
specific selections, including the deployed Grafana models. Empty mutation,
replication, dictionary and detached-part panels are expected when those
resources are absent or idle.

The Overview dashboard (`clickhouse-overview-dashboard.json`) filters Kubernetes
cluster, namespace, pod and PVC dynamically. The PVC list intersects pod volume
metadata with ClickHouse scrape targets so All cannot include Keeper, Grafana
or PostgreSQL PVCs. CPU and memory use cAdvisor consumption plus cgroup limits;
MergeTree data bytes are distinct from total filesystem usage.

The IOPS and MB/s panels use Longhorn's existing per-volume rate gauges for
reads, writes and their total. Shared reference lines are editable inputs:
6,000 IOPS and 48 MB/s for the current 100 GB Balanced (10 VPU/GB) boot volume,
verified in the compute Terraform state. These are nominal physical-disk
references shared with the node's other workloads, not per-PVC reservations.
Throughput uses decimal MB/s (bytes/s divided by 1,000,000). Update the inputs
when changing the boot-volume size or performance tier. See
https://docs.oracle.com/en-us/iaas/Content/Block/Concepts/blockvolumebalancedperformance.htm.
Overview's 29 queries and four query variables are validated with All and
individual selections, including numeric data and isolation of the ClickHouse
PVC. Metrics come from the existing ClickHouse, cAdvisor and Longhorn exporters.

The five legacy ConfigMap dashboards and their sidecar/provider are removed.
Datasources and the CPU recording rule remain provisioned by Helm. The Git Sync
connection and token configured in Grafana persist on its existing data PVC.

The official **CloudNativePG** dashboard comes from the `cluster` chart 0.0.5
in https://github.com/cloudnative-pg/grafana-dashboards. The upstream alert list
panel is retained even when no alert rules exist.
Local adaptations use `$__rate_interval` for the 60-second scrape interval,
match the operator release name and include the `postgres` database containing
the application schemas. I/O, deadlock and temporary-file panels cover
non-template databases and shared objects, rather than only the shared-object
row with an empty database name. The initial time range is one hour.
CPU/memory percentages and the resource-health summary use allocatable capacity
on the nodes hosting the selected instances; PostgreSQL has no resource requests.
The gauges are explicitly labelled `CPU / Node` and `Memory / Node`.
`kube-state-metrics` chart 8.8.0 supplies a small allowlist of pod/node metadata.
Grafana provisions the required CPU recording rule and writes its output to
ClickHouse using the existing writer credential through a dedicated target
datasource. There are no alert rules or notifications.

ClickHouse dashboard JSON filenames include `dashboard`. PostgreSQL panels
for standby-only lag, backups, separate WAL PVCs and tablespaces can be empty
when those features are not configured on the single-instance database.
The CNPG operator chart is pinned to 0.28.3 (operator 1.29.1): 0.28.1 contained
a trailing quote in the `pg_replication` monitoring SQL, preventing its metrics
from being exported. The upstream patch fixes the query without SQL overrides
or changes to PostgreSQL workload resources.

Core panels are validated through Grafana using short rate windows, including
all CPU/memory/connection summary queries.

## Storage, bootstrap and upgrades

Longhorn PVC requests: ClickHouse 20 GiB, Keeper 1 GiB, Grafana 1 GiB,
with one Longhorn replica. This is a single-node deployment with no failover.
ClickHouse has a 2.5 GiB container memory limit and 2 GiB server memory budget.
Collector file checkpoints and export queue use persistent node directories.

`clickhouse-bootstrap-v3` is an idempotent GitOps Job. It creates databases,
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
