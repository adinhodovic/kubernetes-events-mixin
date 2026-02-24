{
  _config+:: {
    local this = self,

    kubernetesEventsSelector: 'job="loki.source.kubernetes_events"',

    // Default datasource name
    datasourceName: 'default',

    // Datasource type for variables (prometheus or loki)
    datasourceType: 'prometheus',

    grafanaUrl: 'https://grafana.com',

    // Opt-in to multiCluster dashboards by overriding this and the clusterLabel.
    showMultiCluster: false,
    clusterLabel: 'cluster',

    // Dashboard panel configuration
    dashboardPanels: {
      // Maximum number of log lines to display in the events logs panel
      maxLinesEventsLogs: 200,
      // Maximum number of log lines to display in the events timeline panel
      maxLinesEventsTimeline: 100,
    },

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
      tags: [],
      datasource: '-- Grafana --',
      iconColor: 'blue',
      type: 'tags',
    },
  },
}
