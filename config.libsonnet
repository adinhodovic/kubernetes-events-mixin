local g = import 'github.com/grafana/grafonnet/gen/grafonnet-latest/main.libsonnet';
local annotation = g.dashboard.annotation;

{
  _config+:: {
    local this = self,

    // Bypasses grafana.com/dashboards validator
    bypassDashboardValidation: {
      __inputs: [],
      __requires: [],
    },

    kubernetesEventsSelector: 'job="loki.source.kubernetes_events"',

    // Default datasource name
    datasourceName: 'default',

    // Datasource type for variables (prometheus or loki)
    datasourceType: 'prometheus',

    grafanaUrl: 'https://grafana.com',

    dashboardIds: {
      'kubernetes-events-overview': 'kubernetes-events-mixin-over-jkwq',
      'kubernetes-events-timeline': 'kubernetes-events-mixin-timeline-jkwq',
    },
    dashboardUrls: {
      'kubernetes-events-overview': '%s/d/%s/kubernetes-events-overview' % [this.grafanaUrl, this.dashboardIds['kubernetes-events-overview']],
      'kubernetes-events-timeline': '%s/d/%s/kubernetes-events-timeline' % [this.grafanaUrl, this.dashboardIds['kubernetes-events-timeline']],
    },

    tags: ['kubernetes', 'kubernetes-events', 'kubernetes-events-mixin'],

    // Custom annotations to display in graphs
    annotation: {
      enabled: false,
      name: 'Custom Annotation',
      datasource: '-- Grafana --',
      iconColor: 'green',
      tags: [],
    },

    customAnnotation:: if $._config.annotation.enabled then
      annotation.withName($._config.annotation.name) +
      annotation.withIconColor($._config.annotation.iconColor) +
      annotation.withHide(false) +
      annotation.datasource.withUid($._config.annotation.datasource) +
      annotation.target.withMatchAny(true) +
      annotation.target.withTags($._config.annotation.tags) +
      annotation.target.withType('tags')
    else {},
  },
}
