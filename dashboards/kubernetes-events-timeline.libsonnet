local g = import 'github.com/grafana/grafonnet/gen/grafonnet-latest/main.libsonnet';

local dashboard = g.dashboard;
local row = g.panel.row;

local variable = dashboard.variable;
local datasource = variable.datasource;
local query = variable.query;
local textbox = variable.textbox;
local loki = g.query.loki;

local logsPanel = g.panel.logs;
local stateTimelinePanel = g.panel.stateTimeline;

// Logs
local lgOptions = logsPanel.options;
local lgQueryOptions = logsPanel.queryOptions;

// State Timeline
local slStandardOptions = stateTimelinePanel.standardOptions;
local slQueryOptions = stateTimelinePanel.queryOptions;

{
  grafanaDashboards+:: {

    local datasourceVariable =
      datasource.new(
        'datasource',
        'loki',
      ) +
      datasource.generalOptions.withLabel('Data source'),

    local jobVariable =
      query.new(
        'job',
      ) +
      query.queryTypes.withLabelValues('job') +
      query.withRegex('.*events.*') +
      query.withDatasourceFromVariable(datasourceVariable) +
      query.withSort(1) +
      query.generalOptions.withLabel('Job') +
      query.refresh.onTime(),

    local kindVariable =
      query.new(
        'kind',
      ) +
      query.withDatasourceFromVariable(datasourceVariable) +
      query.withSort(1) +
      query.generalOptions.withLabel('Kind') +
      query.refresh.onLoad() +
      query.refresh.onTime() +
      // TODO(adinhodovic): Replace this with the grafonnet lib
      {
        query: {
          label: 'k8s_resource_kind',
          stream: '{job=~"$job"}',
          type: '1',
        },
      },

    local namespaceVariable =
      query.new(
        'namespace',
      ) +
      query.withDatasourceFromVariable(datasourceVariable) +
      query.withSort(1) +
      query.generalOptions.withLabel('Namespace') +
      query.refresh.onLoad() +
      query.refresh.onTime() +
      // TODO(adinhodovic): Replace this with the grafonnet lib
      {
        query: {
          label: 'k8s_namespace_name',
          stream: '{job=~"$job", k8s_resource_kind="$kind"}',
          type: '1',
        },
      },

    local nameVariable =
      // workaround for the name variable
      variable.query.new(
        'name'
      ) +
      {
        type: 'textbox',
      } +
      textbox.generalOptions.withLabel('Name') +
      textbox.generalOptions.withDescription('Name of the Kubernetes resource. Use the search, otherwise there is too many unique resources.'),

    local searchVariable =
      // workaround for the textbox variable
      variable.query.new(
        'search'
      ) +
      {
        type: 'textbox',
      } +
      textbox.generalOptions.withLabel('Search') +
      textbox.generalOptions.withDescription('Generic search of the event.'),

    local variables = [
      datasourceVariable,
      jobVariable,
      kindVariable,
      namespaceVariable,
      nameVariable,
      searchVariable,
    ],

    local eventsQuery = |||
      {job=~"$job", k8s_resource_kind="$kind", k8s_namespace_name="$namespace"} | k8s_resource_name=~"$name.*" |~ "$search" | json | line_format "Name: {{ .name }}\nType: {{ .type }}\nReason: {{.reason}}\nMsg: {{.msg}}"
    |||,

    local eventsLogsPanel =
      logsPanel.new(
        'Events',
      ) +
      logsPanel.panelOptions.withDescription('Logs of events for the selected Kubernetes resource. Log line limit is at 100 events.') +
      lgQueryOptions.withTargets(
        loki.new(
          '$datasource',
          eventsQuery,
        ) +
        loki.withMaxLines(100)
      ) +
      lgOptions.withShowTime(true) +
      lgOptions.withWrapLogMessage(true) +
      lgOptions.withEnableLogDetails(true),


    local eventsTimelineQuery = |||
      {job="$job", k8s_resource_kind="$kind", k8s_namespace_name="$namespace"} | k8s_resource_name=~"$name.*" |~ "$search" | json | line_format `{"{{ .kind }} / {{ .name }}": "Type: {{ .type }} | Reason: {{ .reason }} | Event: {{ .msg | replace "\"" "'" }}"}`
    |||,

    local eventsTimelinePanel =
      stateTimelinePanel.new(
        'Events Timeline',
      ) +
      stateTimelinePanel.panelOptions.withDescription('Timeline of events for the selected Kubernetes resource. Please use the search filter, otherwise there will be too many events. Log line limit is at 50 events.') +
      slQueryOptions.withTargets(
        loki.new(
          '$datasource',
          eventsTimelineQuery,
        ) +
        loki.withMaxLines(50)
      ) +
      slQueryOptions.withTransformations(
        slQueryOptions.transformation.withId('extractFields') +
        slQueryOptions.transformation.withOptions(
          {
            delimiter: ',',
            format: 'json',
            keepTime: true,
            replace: true,
            source: 'Line',
          },
        )
      ) +
      slStandardOptions.withMappings(
        [
          slStandardOptions.mapping.RegexMap.withType() +
          slStandardOptions.mapping.RegexMap.options.withPattern('.*Normal.*') +
          slStandardOptions.mapping.RegexMap.options.result.withColor('green') +
          slStandardOptions.mapping.RegexMap.options.result.withIndex(0),
          slStandardOptions.mapping.RegexMap.withType() +
          slStandardOptions.mapping.RegexMap.options.withPattern('.*Warning.*') +
          slStandardOptions.mapping.RegexMap.options.result.withColor('orange') +
          slStandardOptions.mapping.RegexMap.options.result.withIndex(1),
        ]
      ) +
      {
        fieldConfig+: {
          defaults+: {
            custom+: {
              insertNulls: 300000,
            },
          },
        },
      },

    local eventsSummaryRow =
      row.new(
        title='Events Logs ($kind / $namespace / $name - name)',
      ),

    'kubernetes-events-mixin-timeline.json':
      $._config.bypassDashboardValidation +
      dashboard.new(
        'Kubernetes / Events / Timeline',
      ) +
      dashboard.withDescription('A dashboard that monitors Kubernetes Events and focuses on giving a timeline for events. It is created using the [kubernetes-events-mixin](https://github.com/adinhodovic/kubernetes-events-mixin).') +
      dashboard.withUid($._config.kubernetesEventsTimelineDashboardUid) +
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
        [
          eventsSummaryRow +
          row.gridPos.withX(0) +
          row.gridPos.withY(0) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
        ] +
        [
          eventsLogsPanel +
          logsPanel.gridPos.withX(0) +
          logsPanel.gridPos.withY(1) +
          logsPanel.gridPos.withW(24) +
          logsPanel.gridPos.withH(8),
        ] +
        [
          eventsTimelinePanel +
          stateTimelinePanel.gridPos.withX(0) +
          stateTimelinePanel.gridPos.withY(9) +
          stateTimelinePanel.gridPos.withW(24) +
          stateTimelinePanel.gridPos.withH(8),
        ]
      ) +
      if $._config.annotation.enabled then
        dashboard.withAnnotations($._config.customAnnotation)
      else {},
  },
}
