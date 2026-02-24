# Prometheus and Loki Monitoring Mixin for Kubernetes Events

A set of Grafana dashboards and Loki rules for Kubernetes Events. It requires Loki and Alloy

## Configuring Loki and Alloy

The following [blog post gives an example on how to configure Loki and Alloy to work with this mixin](https://hodovi.cc/blog/kubernetes-events-monitoring-with-loki-alloy-and-grafana/).

### Alloy Configuration

Deploy Alloy using Helm with the following values to scrape Kubernetes events and forward them to Loki:

```yaml
alloy:
  configMap:
    content: |
      loki.process "default" {
        stage.replace {
          expression = "(\"type\":\"Normal\")"
          replace = "\"type\":\"Normal\",\"level\":\"info\""
        }
        forward_to = [loki.write.default.receiver]
        stage.replace {
          expression = "(\"type\":\"Warning\")"
          replace = "\"type\":\"Warning\",\"level\":\"warning\""
        }
        stage.json {
          expressions = {
            "k8s_resource_kind" = "kind",
            "k8s_resource_name" = "name",
            "k8s_event_type" = "type",
          }
        }
        stage.labels {
          values = {
              k8s_resource_kind: 'k8s_resource_kind',
              k8s_resource_name: 'k8s_resource_name',
              k8s_event_type: 'k8s_event_type',
                // This comes with alloy's event source.
              k8s_namespace_name: 'namespace',
          }
        }
        stage.structured_metadata {
          values = {
            "k8s_resource_name" = "k8s_resource_name"
          }
        }
        stage.label_keep {
          values = ["cluster", "organization", "region", "job", "k8s_namespace_name", "k8s_resource_kind", "k8s_event_type"]
        }
      }
      loki.source.kubernetes_events "default" {
        forward_to = [loki.process.default.receiver]
        log_format = "json"
      }
      loki.write "default" {
        endpoint {
          url = "http://loki-gateway.logging.svc/loki/api/v1/push"
        }
        external_labels = {
          "cluster" = "my-cluster",
          "environment" = "production",
          "region" = "europe-west1",
        }
      }
    enabled: true
controller:
  type: statefulset
```

The configuration performs the following actions:

- `loki.source.kubernetes_events` - Scrapes the Kubernetes events and forwards them to the Loki processor.
- `loki.process` - Handles the Kubernetes events by replacing the `type` field with `level`, and adds labels and structured metadata. The structured metadata is crucial for filtering and searching the events. Grafana utilizes the `level` field to assess the severity of the event. The label `k8s_resource_kind` differentiates between various Kubernetes kinds alongside `k8s_namespace_name`, which indicates the namespace the resource kind is in.
- `loki.write` - Forwards the processed events to Loki. The `external_labels` field adds additional labels to the events, such as the cluster, environment, and region.
- `controller` - Deploys Alloy as a statefulset. Only a single instance of Alloy is needed to scrape Kubernetes events.

You can verify events are flowing into Loki by querying:

```logql
sum (count_over_time({job="loki.source.kubernetes_events"} | json [1m])) by (k8s_namespace_name, k8s_resource_kind, type)
```

### Loki Configuration

To write metrics from Loki to Prometheus, deploy Loki using Helm with the following values:

```yaml
loki:
  rulerConfig:
    remote_write:
      client:
        url: http://prometheus-k8s.monitoring.svc:9090/api/v1/write
      enabled: true
    rule_path: /rules
    storage:
      local:
        directory: /rules
      type: local
    wal:
      dir: /var/loki/ruler/wal
```

Replace `prometheus-k8s.monitoring.svc` with your Prometheus service endpoint.

Loki also requires a sidecar to load rules from `ConfigMaps`:

```yaml
sidecar:
  rules:
    folder: /rules/fake
    label: loki.grafana.com/rule
    labelValue: "true"
    searchNamespace: ALL
```

The sidecar loads rules from `ConfigMaps` labeled `loki.grafana.com/rule=true` and stores them in `/rules/fake` (the `fake` tenant folder used by single-tenant deployments).

### Loki Recording Rules

Create a `ConfigMap` with the recording rules that write Kubernetes event counts to Prometheus:

```yaml
apiVersion: v1
data:
  kubernetes-events.yaml: |-
    "groups":
    - "interval": "1m"
      "name": "kubernetes-events.rules"
      "rules":
      - "expr": |
          sum (count_over_time({job="loki.source.kubernetes_events"} | json [1m])) by (k8s_namespace_name, k8s_resource_kind, type)
        "record": "namespace_kind_type:kubernetes_events:count1m"
kind: ConfigMap
metadata:
  labels:
    loki.grafana.com/rule: "true"
  name: kubernetes-events
  namespace: logging
```

Once configured correctly, the following metric will be available in Prometheus:

```promql
namespace_kind_type:kubernetes_events:count1m
```

## How to use the mixin

This mixin is designed to be vendored into the repo with your infrastructure config. To do this, use [jsonnet-bundler](https://github.com/jsonnet-bundler/jsonnet-bundler):

You then have three options for deploying your dashboards

1. Generate the config files and deploy them yourself
2. Use jsonnet to deploy this mixin along with Prometheus and Grafana
3. Use prometheus-operator to deploy this mixin

Or import the dashboard using json in `./dashboards_out`, alternatively import them from the `Grafana.com` dashboard page.

## Generate config files

You can manually generate the alerts, dashboards and rules files, but first you must install some tools:

```sh
go get github.com/jsonnet-bundler/jsonnet-bundler/cmd/jb
brew install jsonnet
```

Then, grab the mixin and its dependencies:

```sh
git clone https://github.com/adinhodovic/kubernetes-events-mixin
cd kubernetes-events
jb install
```

Finally, build the mixin:

```sh
make prometheus_rules.yaml
make dashboards_out
```

The `prometheus_rules.yaml` file then need to passed to your Loki server, and the files in `dashboards_out` need to be imported into you Grafana server. The exact details will depending on how you deploy your monitoring stack.
