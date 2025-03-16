# Prometheus and Loki Monitoring Mixin for Kubernetes Events

A set of Grafana dashboards and Loki rules for Kubernetes Events.

## How to use

This mixin is designed to be vendored into the repo with your infrastructure config.
To do this, use [jsonnet-bundler](https://github.com/jsonnet-bundler/jsonnet-bundler):

You then have three options for deploying your dashboards

1. Generate the config files and deploy them yourself
2. Use jsonnet to deploy this mixin along with Prometheus and Grafana
3. Use prometheus-operator to deploy this mixin

Or import the dashboard using json in `./dashboards_out`, alternatively import them from the `Grafana.com` dashboard page.

## Generate config files

You can manually generate the alerts, dashboards and rules files, but first you
must install some tools:

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

The `prometheus_rules.yaml` file then need to passed
to your Prometheus server, and the files in `dashboards_out` need to be imported
into you Grafana server. The exact details will depending on how you deploy your
monitoring stack.

## Loki Rules

Note: The rules outputted by this mixin are intended to be used with Loki. This means that a `remote_write` configuration is required in your Loki setup and the rules should be picked up by Loki, not by Prometheus. The rules generate Prometheus metrics from the Loki logs, which can then be queried in Grafana.

Read: [Loki Remote Write](https://grafana.com/docs/loki/latest/alert/#remote-write)
