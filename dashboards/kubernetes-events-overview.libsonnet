local g = import 'github.com/grafana/grafonnet/gen/grafonnet-latest/main.libsonnet';

local dashboard = g.dashboard;
local row = g.panel.row;
local grid = g.util.grid;

local variable = dashboard.variable;
local datasource = variable.datasource;
local query = variable.query;
local textbox = variable.textbox;
local loki = g.query.loki;
local prometheus = g.query.prometheus;

local statPanel = g.panel.stat;
local logsPanel = g.panel.logs;
local timeSeriesPanel = g.panel.timeSeries;
local tablePanel = g.panel.table;
local pieChartPanel = g.panel.pieChart;
local stateTimelinePanel = g.panel.stateTimeline;

// Stat
local stOptions = statPanel.options;
local stStandardOptions = statPanel.standardOptions;
local stQueryOptions = statPanel.queryOptions;

// Logs
local lgOptions = logsPanel.options;
local lgStandardOptions = logsPanel.standardOptions;
local lgQueryOptions = logsPanel.queryOptions;

// State Timeline
local slOptions = stateTimelinePanel.options;
local slStandardOptions = stateTimelinePanel.standardOptions;
local slQueryOptions = stateTimelinePanel.queryOptions;

// Timeseries
local tsOptions = timeSeriesPanel.options;
local tsStandardOptions = timeSeriesPanel.standardOptions;
local tsQueryOptions = timeSeriesPanel.queryOptions;
local tsFieldConfig = timeSeriesPanel.fieldConfig;
local tsCustom = tsFieldConfig.defaults.custom;
local tsLegend = tsOptions.legend;

// Table
local tbOptions = tablePanel.options;
local tbStandardOptions = tablePanel.standardOptions;
local tbQueryOptions = tablePanel.queryOptions;
local tbFieldConfig = tablePanel.fieldConfig;
local tbPanelOptions = tablePanel.panelOptions;
local tbOverride = tbStandardOptions.override;

// Pie Chart
local pieOptions = pieChartPanel.options;
local pieStandardOptions = pieChartPanel.standardOptions;
local pieQueryOptions = pieChartPanel.queryOptions;

{
  grafanaDashboards+:: {

    local datasourceVariable =
      datasource.new(
        'datasource',
        'loki',
      ) +
      datasource.generalOptions.withLabel('Loki Data source'),

    local prometheusDatasourceVariable =
      datasource.new(
        'prometheus_datasource',
        'prometheus',
      ) +
      datasource.generalOptions.withLabel('Prometheus Data source'),

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
      textbox.new(
        'name',
      ) +
      textbox.generalOptions.withLabel('Name') +
      textbox.generalOptions.withDescription('Name of the Kubernetes resource. Use the search, otherwise there is too many unique resources.'),

    local searchVariable =
      textbox.new(
        'search',
      ) +
      textbox.generalOptions.withLabel('Search') +
      textbox.generalOptions.withDescription('Generic search of the event.'),

    local variables = [
      datasourceVariable,
      prometheusDatasourceVariable,
      jobVariable,
      kindVariable,
      namespaceVariable,
      nameVariable,
      searchVariable,
    ],

    local eventsCountSumQuery = |||
      sum(namespace_kind_type:kubernetes_events:count1m) by (k8s_resource_kind, k8s_namespace_name, type)
    ||| % $._config,

    local eventCountSumTimeSeriesPanel =
      timeSeriesPanel.new(
        'Events',
      ) +
      tsQueryOptions.withTargets(
        [
          prometheus.new(
            '$prometheus_datasource',
            eventsCountSumQuery,
          ) +
          prometheus.withLegendFormat(
            '{{k8s_resource_kind}} / {{k8s_namespace_name}} / {{type}}'
          ),
        ]
      ) +
      tsStandardOptions.withUnit('short') +
      tsOptions.tooltip.withMode('multi') +
      tsOptions.tooltip.withSort('desc') +
      tsLegend.withShowLegend(true) +
      tsLegend.withDisplayMode('table') +
      tsLegend.withPlacement('right') +
      tsLegend.withCalcs(['lastNotNull', 'mean', 'max']) +
      tsLegend.withSortBy('Last *') +
      tsLegend.withSortDesc(true) +
      tsCustom.stacking.withMode('normal') +
      tsCustom.withFillOpacity(100) +
      tsCustom.withSpanNulls(false),

    local eventsCountNormalSumQuery = |||
      topk(10, sum(count_over_time(namespace_kind_type:kubernetes_events:count1m{type="Normal"}[24h])) by (k8s_resource_kind, k8s_namespace_name))
    ||| % $._config,

    local eventsCountNormalSumTable =
      tablePanel.new(
        'Top 10 Normal Event Emissions by Kind and Namespace[24h]',
      ) +
      tbStandardOptions.withUnit('short') +
      tbOptions.withSortBy(
        tbOptions.sortBy.withDisplayName('Node Pool')
      ) +
      tbOptions.footer.withEnablePagination(true) +
      tbQueryOptions.withTargets(
        [
          prometheus.new(
            '$prometheus_datasource',
            eventsCountNormalSumQuery,
          ) +
          prometheus.withInstant(true) +
          prometheus.withFormat('table'),
        ]
      ) +
      tbQueryOptions.withTransformations([
        tbQueryOptions.transformation.withId(
          'organize'
        ) +
        tbQueryOptions.transformation.withOptions(
          {
            renameByName: {
              k8s_resource_kind: 'Kind',
              k8s_namespace_name: 'Namespace',
            },
            indexByName: {
              Kind: 0,
              Namespace: 1,
            },
            excludeByName: {
              Time: true,
              job: true,
            },
          }
        ),
      ]),

    local eventsCountWarningSumQuery = std.strReplace(eventsCountNormalSumQuery, 'Normal', 'Warning'),

    local eventsCountWarningSumTable =
      tablePanel.new(
        'Top 10 Warning Event Emissions by Kind and Namespace[24h]',
      ) +
      tbStandardOptions.withUnit('short') +
      tbOptions.withSortBy(
        tbOptions.sortBy.withDisplayName('Node Pool')
      ) +
      tbOptions.footer.withEnablePagination(true) +
      tbQueryOptions.withTargets(
        [
          prometheus.new(
            '$prometheus_datasource',
            eventsCountWarningSumQuery,
          ) +
          prometheus.withInstant(true) +
          prometheus.withFormat('table'),
        ]
      ) +
      tbQueryOptions.withTransformations([
        tbQueryOptions.transformation.withId(
          'organize'
        ) +
        tbQueryOptions.transformation.withOptions(
          {
            renameByName: {
              k8s_resource_kind: 'Kind',
              k8s_namespace_name: 'Namespace',
            },
            indexByName: {
              Kind: 0,
              Namespace: 1,
            },
            excludeByName: {
              Time: true,
              job: true,
            },
          }
        ),
      ]),

    local eventsCountQuery = |||
      sum(count_over_time(namespace_kind_type:kubernetes_events:count1m{k8s_resource_kind="$kind", k8s_namespace_name="$namespace"}[24h]))
    ||| % $._config,

    local eventsCountStatPanel =
      statPanel.new(
        'Events[24h]',
      ) +
      stQueryOptions.withTargets(
        prometheus.new(
          '$prometheus_datasource',
          eventsCountQuery,
        )
      ) +
      stStandardOptions.withUnit('short') +
      stOptions.reduceOptions.withCalcs(['lastNotNull']) +
      stStandardOptions.thresholds.withSteps([
        stStandardOptions.threshold.step.withValue(0) +
        stStandardOptions.threshold.step.withColor('red'),
        stStandardOptions.threshold.step.withValue(0.1) +
        stStandardOptions.threshold.step.withColor('green'),
      ]),

    local eventsNormalCountQuery = |||
      count_over_time(namespace_kind_type:kubernetes_events:count1m{k8s_resource_kind="$kind", k8s_namespace_name="$namespace", type="Normal"}[24h])
    |||,

    local eventsNormalCountStatPanel =
      statPanel.new(
        'Events Normal[24h]',
      ) +
      stQueryOptions.withTargets(
        prometheus.new(
          '$prometheus_datasource',
          eventsNormalCountQuery,
        )
      ) +
      stStandardOptions.withUnit('short') +
      stOptions.reduceOptions.withCalcs(['lastNotNull']) +
      stStandardOptions.thresholds.withSteps([
        stStandardOptions.threshold.step.withValue(0) +
        stStandardOptions.threshold.step.withColor('red'),
        stStandardOptions.threshold.step.withValue(0.1) +
        stStandardOptions.threshold.step.withColor('green'),
      ]),

    local eventsWarningCountQuery = std.strReplace(eventsNormalCountQuery, 'Normal', 'Warning'),

    local eventsWarningCountStatPanel =
      statPanel.new(
        'Events Warning[24h]',
      ) +
      stQueryOptions.withTargets(
        prometheus.new(
          '$prometheus_datasource',
          eventsWarningCountQuery,
        )
      ) +
      stStandardOptions.withUnit('short') +
      stOptions.reduceOptions.withCalcs(['lastNotNull']) +
      stStandardOptions.thresholds.withSteps([
        stStandardOptions.threshold.step.withValue(0) +
        stStandardOptions.threshold.step.withColor('red'),
        stStandardOptions.threshold.step.withValue(0.1) +
        stStandardOptions.threshold.step.withColor('green'),
      ]),

    local eventsCountByTypeQuery = |||
      sum(namespace_kind_type:kubernetes_events:count1m{k8s_resource_kind="$kind", k8s_namespace_name="$namespace"}) by ( type)
    ||| % $._config,

    local eventCountByTypeTimeSeriesPanel =
      timeSeriesPanel.new(
        'Events by Type',
      ) +
      tsQueryOptions.withTargets(
        [
          prometheus.new(
            '$prometheus_datasource',
            eventsCountByTypeQuery,
          ) +
          prometheus.withLegendFormat(
            '{{type}}'
          ),
        ]
      ) +
      tsStandardOptions.withUnit('short') +
      tsOptions.tooltip.withMode('multi') +
      tsOptions.tooltip.withSort('desc') +
      tsLegend.withShowLegend(true) +
      tsLegend.withDisplayMode('table') +
      tsLegend.withPlacement('right') +
      tsLegend.withCalcs(['lastNotNull', 'mean', 'max']) +
      tsLegend.withSortBy('Last *') +
      tsLegend.withSortDesc(true) +
      tsCustom.stacking.withMode('normal') +
      tsCustom.withFillOpacity(100) +
      tsCustom.withSpanNulls(false),

    local eventsQuery = |||
      {job=~"$job", k8s_resource_kind="$kind", k8s_namespace_name="$namespace"} | k8s_resource_name=~"$name.*" |~ "$search" | json | line_format "Name: {{ .name }}\nType: {{ .type }}\nReason: {{.reason}}\nMsg: {{.msg}}"
    |||,

    local eventsLogsPanel =
      logsPanel.new(
        'Events',
      ) +
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

    local summaryRow =
      row.new(
        title='Summary',
      ),

    local eventsKindSummaryRow =
      row.new(
        title='Kind Summary ($kind / $namespace)',
      ),

    local eventsSummaryRow =
      row.new(
        title='Events Logs ($kind / $namespace / $name - name)',
      ),

    'kubernetes-events-mixin-overview.json':
      $._config.bypassDashboardValidation +
      dashboard.new(
        'Kubernetes / Events / Overview',
      ) +
      dashboard.withDescription('A dashboard that monitors Kubernetes Events and focuses on giving a overview for events. It is created using the [kubernetes-events-mixin](https://github.com/adinhodovic/kubernetes-events-mixin).') +
      dashboard.withUid($._config.kubernetesEventsOverviewDashboardUid) +
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
          summaryRow +
          row.gridPos.withX(0) +
          row.gridPos.withY(0) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
        ] +
        [
          eventCountSumTimeSeriesPanel +
          timeSeriesPanel.gridPos.withX(0) +
          timeSeriesPanel.gridPos.withY(1) +
          timeSeriesPanel.gridPos.withW(24) +
          timeSeriesPanel.gridPos.withH(6),
        ] +
        grid.makeGrid(
          [
            eventsCountNormalSumTable,
            eventsCountWarningSumTable,
          ],
          panelWidth=12,
          panelHeight=8,
          startY=7
        ) +
        [
          eventsKindSummaryRow +
          row.gridPos.withX(0) +
          row.gridPos.withY(15) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
        ] +
        grid.makeGrid(
          [
            eventsCountStatPanel,
            eventsNormalCountStatPanel,
            eventsWarningCountStatPanel,
          ],
          panelWidth=8,
          panelHeight=3,
          startY=16
        ) +
        [
          eventCountByTypeTimeSeriesPanel +
          timeSeriesPanel.gridPos.withX(0) +
          timeSeriesPanel.gridPos.withY(19) +
          timeSeriesPanel.gridPos.withW(24) +
          timeSeriesPanel.gridPos.withH(6),
        ] +
        [
          eventsSummaryRow +
          row.gridPos.withX(0) +
          row.gridPos.withY(23) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
        ] +
        [
          eventsLogsPanel +
          logsPanel.gridPos.withX(0) +
          logsPanel.gridPos.withY(24) +
          logsPanel.gridPos.withW(24) +
          logsPanel.gridPos.withH(8),
        ] +
        [
          eventsTimelinePanel +
          stateTimelinePanel.gridPos.withX(0) +
          stateTimelinePanel.gridPos.withY(32) +
          stateTimelinePanel.gridPos.withW(24) +
          stateTimelinePanel.gridPos.withH(8),
        ]
      ) +
      if $._config.annotation.enabled then
        dashboard.withAnnotations($._config.customAnnotation)
      else {},
  },
}
