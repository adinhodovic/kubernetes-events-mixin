local g = import 'github.com/grafana/grafonnet/gen/grafonnet-latest/main.libsonnet';

local dashboard = g.dashboard;
local row = g.panel.row;
local grid = g.util.grid;

local variable = dashboard.variable;
local datasource = variable.datasource;
local query = variable.query;
local prometheus = g.query.prometheus;

local timeSeriesPanel = g.panel.timeSeries;
local tablePanel = g.panel.table;
local pieChartPanel = g.panel.pieChart;

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
local tbPanelOptions = tablePanel.panelOptions;
local tbOverride = tbStandardOptions.override;

// Pie Chart
local pcOptions = pieChartPanel.options;
local pcStandardOptions = pieChartPanel.standardOptions;
local pcQueryOptions = pieChartPanel.queryOptions;
local pcOverride = pcStandardOptions.override;

{
  grafanaDashboards+:: {

    local prometheusDatasourceVariable =
      datasource.new(
        'prometheus_datasource',
        'prometheus',
      ) +
      datasource.generalOptions.withLabel('Prometheus data source'),

    local lokiDatasourceVariable =
      datasource.new(
        'loki_datasource',
        'loki',
      ) +
      datasource.generalOptions.withLabel('Loki data source'),

    local jobVariable =
      query.new(
        'job',
      ) +
      query.queryTypes.withLabelValues('job') +
      query.withRegex('.*events.*') +
      query.withDatasourceFromVariable(lokiDatasourceVariable) +
      query.withSort(1) +
      query.generalOptions.withLabel('Job') +
      query.refresh.onTime(),

    local kindVariable =
      query.new(
        'kind',
      ) +
      query.withDatasourceFromVariable(lokiDatasourceVariable) +
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
      query.withDatasourceFromVariable(lokiDatasourceVariable) +
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

    local variables = [
      prometheusDatasourceVariable,
      lokiDatasourceVariable,
      jobVariable,
      kindVariable,
      namespaceVariable,
    ],

    local eventsCountSumQuery = |||
      sum(namespace_kind_type:kubernetes_events:count1m) by (k8s_resource_kind, k8s_namespace_name, type)
    ||| % $._config,

    local eventCountSumTimeSeriesPanel =
      timeSeriesPanel.new(
        'Events',
      ) +
      timeSeriesPanel.panelOptions.withDescription('Total Event Emissions by Kind and Namespace[1w]') +
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
      topk(10, sum(count_over_time(namespace_kind_type:kubernetes_events:count1m{type="Normal"}[1w])) by (k8s_resource_kind, k8s_namespace_name))
    ||| % $._config,

    local eventsCountNormalSumTable =
      tablePanel.new(
        'Top 10 Normal Event Emissions by Kind and Namespace[1w]',
      ) +
      tablePanel.panelOptions.withDescription('Top 10 Normal Event Emissions by Kind and Namespace[1w]') +
      tbStandardOptions.withUnit('short') +
      tbOptions.withSortBy(
        tbOptions.sortBy.withDisplayName('Value') +
        tbOptions.sortBy.withDesc(true)
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
              k8s_resource_kind: 0,
              k8s_namespace_name: 1,
            },
            excludeByName: {
              Time: true,
              job: true,
            },
          }
        ),
      ]) +
      tbStandardOptions.withOverrides([
        tbOverride.byName.new('Kind') +
        tbOverride.byName.withPropertiesFromOptions(
          tbStandardOptions.withLinks(
            tbPanelOptions.link.withTitle('Go To Timeline') +
            tbPanelOptions.link.withType('dashboard') +
            tbPanelOptions.link.withUrl(
              '/d/%s/kubernetes-events-timeline?var-kind=${__data.fields.Kind}&var-namespace=${__data.fields.Namespace}' % $._config.kubernetesEventsTimelineDashboardUid
            ) +
            tbPanelOptions.link.withTargetBlank(true)
          )
        ),
      ]),

    local eventsCountWarningSumQuery = std.strReplace(eventsCountNormalSumQuery, 'Normal', 'Warning'),

    local eventsCountWarningSumTable =
      tablePanel.new(
        'Top 10 Warning Event Emissions by Kind and Namespace[1w]',
      ) +
      tablePanel.panelOptions.withDescription('Top 10 Warning Event Emissions by Kind and Namespace[1w]') +
      tbStandardOptions.withUnit('short') +
      tbOptions.withSortBy(
        tbOptions.sortBy.withDisplayName('Value') +
        tbOptions.sortBy.withDesc(true)
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
              k8s_resource_kind: 0,
              k8s_namespace_name: 1,
            },
            excludeByName: {
              Time: true,
              job: true,
            },
          }
        ),
      ]) +
      tbStandardOptions.withOverrides([
        tbOverride.byName.new('Kind') +
        tbOverride.byName.withPropertiesFromOptions(
          tbStandardOptions.withLinks(
            tbPanelOptions.link.withTitle('Go To Timeline') +
            tbPanelOptions.link.withType('dashboard') +
            tbPanelOptions.link.withUrl(
              '/d/%s/kubernetes-events-timeline?var-kind=${__data.fields.Kind}&var-namespace=${__data.fields.Namespace}' % $._config.kubernetesEventsTimelineDashboardUid
            ) +
            tbPanelOptions.link.withTargetBlank(true)
          )
        ),
      ]),

    local eventsCountByType1wQuery = |||
      sum(count_over_time(namespace_kind_type:kubernetes_events:count1m{k8s_resource_kind="$kind", k8s_namespace_name="$namespace"}[1w])) by (type)
    |||,


    local eventsCountByType1wPieChartPanel =
      pieChartPanel.new(
        'Events by Type[1w]'
      ) +
      pieChartPanel.panelOptions.withDescription('Events by Type[1w]') +
      pcQueryOptions.withTargets(
        prometheus.new(
          '$prometheus_datasource',
          eventsCountByType1wQuery,
        ) +
        prometheus.withLegendFormat('{{ type }}') +
        prometheus.withInstant(true)
      ) +
      pcOptions.withPieType('pie') +
      pcOptions.legend.withAsTable(true) +
      pcOptions.legend.withPlacement('right') +
      pcOptions.legend.withDisplayMode('table') +
      pcOptions.legend.withValues(['value', 'percent']) +
      pcOptions.legend.withSortDesc(true) +
      pcStandardOptions.withOverrides([
        pcOverride.byName.new('Normal') +
        pcOverride.byName.withPropertiesFromOptions(
          pcStandardOptions.color.withMode('fixed') +
          pcStandardOptions.color.withFixedColor('green')
        ),
        pcOverride.byName.new('Warning') +
        pcOverride.byName.withPropertiesFromOptions(
          pcStandardOptions.color.withMode('fixed') +
          pcStandardOptions.color.withFixedColor('yellow')
        ),
      ]),

    local eventsCountByTypeQuery = |||
      sum(namespace_kind_type:kubernetes_events:count1m{k8s_resource_kind="$kind", k8s_namespace_name="$namespace"}) by ( type)
    ||| % $._config,

    local eventCountByTypeTimeSeriesPanel =
      timeSeriesPanel.new(
        'Events by Type',
      ) +
      timeSeriesPanel.panelOptions.withDescription('Events by Type') +
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

    local summaryRow =
      row.new(
        title='Summary',
      ),

    local eventsKindSummaryRow =
      row.new(
        title='Kind Summary ($kind / $namespace)',
      ),

    'kubernetes-events-mixin-overview.json':
      $._config.bypassDashboardValidation +
      dashboard.new(
        'Kubernetes / Events / Overview',
      ) +
      dashboard.withDescription('A dashboard that monitors Kubernetes Events and focuses on giving a overview for events. It is created using the [kubernetes-events-mixin](https://github.com/adinhodovic/kubernetes-events-mixin). A pre requisite is configuring Loki, Alloy and Prometheus - it is described in this blog post: https://hodovi.cc/blog/kubernetes-events-monitoring-with-loki-alloy-and-grafana/') +
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
        [
          eventsCountByType1wPieChartPanel +
          pieChartPanel.gridPos.withX(0) +
          pieChartPanel.gridPos.withY(16) +
          pieChartPanel.gridPos.withW(6) +
          pieChartPanel.gridPos.withH(6),
          eventCountByTypeTimeSeriesPanel +
          timeSeriesPanel.gridPos.withX(6) +
          timeSeriesPanel.gridPos.withY(16) +
          timeSeriesPanel.gridPos.withW(18) +
          timeSeriesPanel.gridPos.withH(6),
        ]
      ) +
      if $._config.annotation.enabled then
        dashboard.withAnnotations($._config.customAnnotation)
      else {},
  },
}
