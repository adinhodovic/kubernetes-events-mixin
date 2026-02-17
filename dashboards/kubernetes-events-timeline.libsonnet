local mixinUtils = import 'github.com/adinhodovic/mixin-utils/utils.libsonnet';
local g = import 'github.com/grafana/grafonnet/gen/grafonnet-latest/main.libsonnet';
local util = import 'util.libsonnet';

local dashboard = g.dashboard;
local row = g.panel.row;

local logsPanel = g.panel.logs;
local stateTimelinePanel = g.panel.stateTimeline;

// State Timeline (for custom configurations not covered by mixinUtils)
local slStandardOptions = stateTimelinePanel.standardOptions;
local slQueryOptions = stateTimelinePanel.queryOptions;

{
  local dashboardName = 'kubernetes-events-timeline',
  grafanaDashboards+:: {
    ['%s.json' % dashboardName]:

      local lokiVariables = util.variables($._config { datasourceType: 'loki' });

      local variables = [
        lokiVariables.datasource,
        lokiVariables.job,
        lokiVariables.kind,
        lokiVariables.namespace,
        lokiVariables.name,
        lokiVariables.search,
      ];

      local queries = {
        events: |||
          {job=~"$job", k8s_resource_kind="$kind", k8s_namespace_name="$namespace"} | k8s_resource_name=~"$name.*" |~ "$search" | json | line_format "Name: {{ .name }}\nType: {{ .type }}\nReason: {{.reason}}\nMsg: {{.msg}}"
        |||,

        eventsTimeline: |||
          {job="$job", k8s_resource_kind="$kind", k8s_namespace_name="$namespace"} | k8s_resource_name=~"$name.*" |~ "$search" | json | line_format `{"{{ .kind }} / {{ .name }}": "Type: {{ .type }} | Reason: {{ .reason }} | Event: {{ .msg | replace "\"" "'" }}"}`
        |||,
      };

      local panels = {
        eventsLogs:
          mixinUtils.dashboards.logsPanel(
            'Events',
            queries.events,
            description='Logs of events for the selected Kubernetes resource. Log line limit is at %d events.' % $._config.dashboardPanels.maxLinesEventsLogs,
            maxLines=$._config.dashboardPanels.maxLinesEventsLogs,
            showTime=true,
            wrapLogMessage=true,
            enableLogDetails=true,
          ),

        eventsTimeline:
          mixinUtils.dashboards.stateTimelinePanel(
            'Events Timeline',
            queries.eventsTimeline,
            description='Timeline of events for the selected Kubernetes resource. Please use the search filter, otherwise there will be too many events. Log line limit is at %d events.' % $._config.dashboardPanels.maxLinesEventsTimeline,
            maxLines=$._config.dashboardPanels.maxLinesEventsTimeline,
            transformations=[
              slQueryOptions.transformation.withId('extractFields') +
              slQueryOptions.transformation.withOptions({
                delimiter: ',',
                format: 'json',
                keepTime: true,
                replace: true,
                source: 'Line',
              }),
            ],
            mappings=[
              slStandardOptions.mapping.RegexMap.withType() +
              slStandardOptions.mapping.RegexMap.options.withPattern('.*Normal.*') +
              slStandardOptions.mapping.RegexMap.options.result.withColor('green') +
              slStandardOptions.mapping.RegexMap.options.result.withIndex(0),
              slStandardOptions.mapping.RegexMap.withType() +
              slStandardOptions.mapping.RegexMap.options.withPattern('.*Warning.*') +
              slStandardOptions.mapping.RegexMap.options.result.withColor('orange') +
              slStandardOptions.mapping.RegexMap.options.result.withIndex(1),
            ],
            insertNulls=300000,
          ),
      };

      local rows =
        [
          row.new('Events Logs ($kind / $namespace / $name - name)') +
          row.gridPos.withX(0) +
          row.gridPos.withY(0) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
        ] +
        [
          panels.eventsLogs +
          logsPanel.gridPos.withX(0) +
          logsPanel.gridPos.withY(1) +
          logsPanel.gridPos.withW(24) +
          logsPanel.gridPos.withH(10),
        ] +
        [
          panels.eventsTimeline +
          stateTimelinePanel.gridPos.withX(0) +
          stateTimelinePanel.gridPos.withY(9) +
          stateTimelinePanel.gridPos.withW(24) +
          stateTimelinePanel.gridPos.withH(12),
        ];


      mixinUtils.dashboards.bypassDashboardValidation +
      dashboard.new(
        'Kubernetes / Events / Timeline',
      ) +
      dashboard.withDescription('A dashboard that monitors Kubernetes Events and focuses on giving a timeline for events. It is created using the [kubernetes-events-mixin](https://github.com/adinhodovic/kubernetes-events-mixin). A pre requisite is configuring Loki, Alloy and Prometheus - it is described in this blog post: https://hodovi.cc/blog/kubernetes-events-monitoring-with-loki-alloy-and-grafana/') +
      dashboard.withUid($._config.dashboardIds[dashboardName]) +
      dashboard.withTags($._config.tags) +
      dashboard.withTimezone('utc') +
      dashboard.withEditable(true) +
      dashboard.time.withFrom('now-3h') +
      dashboard.time.withTo('now') +
      dashboard.withVariables(variables) +
      dashboard.withLinks(
        [
          dashboard.link.dashboards.new('Kubernetes Events', $._config.tags) +
          dashboard.link.link.options.withTargetBlank(true),
        ]
      ) +
      dashboard.withPanels(
        rows
      ),
  },
}
