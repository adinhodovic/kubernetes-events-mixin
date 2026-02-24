local mixinUtils = import 'github.com/adinhodovic/mixin-utils/utils.libsonnet';
local g = import 'github.com/grafana/grafonnet/gen/grafonnet-latest/main.libsonnet';
local util = import 'util.libsonnet';

local dashboard = g.dashboard;
local row = g.panel.row;
local grid = g.util.grid;

local timeSeriesPanel = g.panel.timeSeries;
local tablePanel = g.panel.table;
local pieChartPanel = g.panel.pieChart;

// Table (for custom configurations not covered by mixinUtils)
local tbStandardOptions = tablePanel.standardOptions;
local tbQueryOptions = tablePanel.queryOptions;
local tbPanelOptions = tablePanel.panelOptions;

// Pie Chart (for custom configurations not covered by mixinUtils)
local pcStandardOptions = pieChartPanel.standardOptions;
local pcOverride = pcStandardOptions.override;

{
  local dashboardName = 'kubernetes-events-overview',
  grafanaDashboards+:: {
    ['%s.json' % dashboardName]:

      local defaultVariables = util.variables($._config);

      local variables = [
        defaultVariables.datasource,
        defaultVariables.cluster,
        defaultVariables.kind,
        defaultVariables.namespace,
      ];

      local defaultFilters = util.filters($._config);

      local timelineLink =
        tbPanelOptions.link.withTitle('Go To Timeline') +
        tbPanelOptions.link.withType('dashboard') +
        tbPanelOptions.link.withUrl(
          '/d/%s/kubernetes-events-timeline?var-cluster=${__data.fields.Cluster}&var-kind=${__data.fields.Kind}&var-namespace=${__data.fields.Namespace}' % $._config.dashboardIds['kubernetes-events-timeline']
        ) +
        tbPanelOptions.link.withTargetBlank(true);

      local queries = {
        // Summary - All Events (cluster-scoped only, no kind/namespace filter)
        eventsCountSum: |||
          sum(namespace_kind_type:kubernetes_events:count1m{%(cluster)s}) by (k8s_resource_kind, k8s_namespace_name, type)
        ||| % defaultFilters,

        eventsCountNormalSum: |||
          topk(10, sum(count_over_time(namespace_kind_type:kubernetes_events:count1m{%(cluster)s, type="Normal"}[1w])) by (cluster, k8s_resource_kind, k8s_namespace_name))
        ||| % defaultFilters,

        eventsCountWarningSum: std.strReplace(self.eventsCountNormalSum, 'Normal', 'Warning'),

        // Kind Summary
        eventsCountByType1w: |||
          sum(count_over_time(namespace_kind_type:kubernetes_events:count1m{%(default)s}[1w])) by (type)
        ||| % defaultFilters,

        eventsCountByType: |||
          sum(namespace_kind_type:kubernetes_events:count1m{%(default)s}) by (type)
        ||| % defaultFilters,
      };

      local panels = {
        // Summary - All Events
        eventCountSumTimeSeries:
          mixinUtils.dashboards.timeSeriesPanel(
            'Events',
            'short',
            queries.eventsCountSum,
            '{{k8s_resource_kind}} / {{k8s_namespace_name}} / {{type}}',
            calcs=['lastNotNull', 'mean', 'max'],
            stack='normal',
            description='Total Event Emissions by Kind and Namespace[1w]',
          ),

        eventsCountNormalSumTable:
          mixinUtils.dashboards.tablePanel(
            'Top 10 Normal Event Emissions by Kind and Namespace[1w]',
            'short',
            queries.eventsCountNormalSum,
            description='Top 10 Normal Event Emissions by Kind and Namespace[1w]',
            sortBy={ name: 'Value', desc: true },
            transformations=[
              tbQueryOptions.transformation.withId('organize') +
              tbQueryOptions.transformation.withOptions({
                renameByName: {
                  cluster: 'Cluster',
                  k8s_resource_kind: 'Kind',
                  k8s_namespace_name: 'Namespace',
                },
                indexByName: {
                  cluster: 0,
                  k8s_resource_kind: 1,
                  k8s_namespace_name: 2,
                },
                excludeByName: {
                  Time: true,
                },
              }),
            ],
          ) +
          tbStandardOptions.withLinks([timelineLink]),

        eventsCountWarningSumTable:
          mixinUtils.dashboards.tablePanel(
            'Top 10 Warning Event Emissions by Kind and Namespace[1w]',
            'short',
            queries.eventsCountWarningSum,
            description='Top 10 Warning Event Emissions by Kind and Namespace[1w]',
            sortBy={ name: 'Value', desc: true },
            transformations=[
              tbQueryOptions.transformation.withId('organize') +
              tbQueryOptions.transformation.withOptions({
                renameByName: {
                  cluster: 'Cluster',
                  k8s_resource_kind: 'Kind',
                  k8s_namespace_name: 'Namespace',
                },
                indexByName: {
                  cluster: 0,
                  k8s_resource_kind: 1,
                  k8s_namespace_name: 2,
                },
                excludeByName: {
                  Time: true,
                },
              }),
            ],
          ) +
          tbStandardOptions.withLinks([timelineLink]),

        // Kind Summary
        eventsCountByType1wPieChart:
          mixinUtils.dashboards.pieChartPanel(
            'Events by Type[1w]',
            'short',
            queries.eventsCountByType1w,
            '{{ type }}',
            description='Events by Type[1w]',
            labels=['value', 'percent'],
            values=['value', 'percent'],
            overrides=[
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
            ]
          ),

        eventCountByTypeTimeSeries:
          mixinUtils.dashboards.timeSeriesPanel(
            'Events by Type',
            'short',
            queries.eventsCountByType,
            '{{type}}',
            calcs=['lastNotNull', 'mean', 'max'],
            stack='normal',
            description='Events by Type',
          ),
      };

      local rows =
        [
          row.new('Summary All Events') +
          row.gridPos.withX(0) +
          row.gridPos.withY(0) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
        ] +
        [
          panels.eventCountSumTimeSeries +
          timeSeriesPanel.gridPos.withX(0) +
          timeSeriesPanel.gridPos.withY(1) +
          timeSeriesPanel.gridPos.withW(24) +
          timeSeriesPanel.gridPos.withH(6),
        ] +
        grid.makeGrid(
          [
            panels.eventsCountNormalSumTable,
            panels.eventsCountWarningSumTable,
          ],
          panelWidth=12,
          panelHeight=8,
          startY=7
        ) +
        [
          row.new('Kind Summary ($kind / $namespace)') +
          row.gridPos.withX(0) +
          row.gridPos.withY(15) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
        ] +
        [
          panels.eventsCountByType1wPieChart +
          pieChartPanel.gridPos.withX(0) +
          pieChartPanel.gridPos.withY(16) +
          pieChartPanel.gridPos.withW(6) +
          pieChartPanel.gridPos.withH(6),
          panels.eventCountByTypeTimeSeries +
          timeSeriesPanel.gridPos.withX(6) +
          timeSeriesPanel.gridPos.withY(16) +
          timeSeriesPanel.gridPos.withW(18) +
          timeSeriesPanel.gridPos.withH(6),
        ];


      mixinUtils.dashboards.bypassDashboardValidation +
      dashboard.new(
        'Kubernetes / Events / Overview',
      ) +
      dashboard.withDescription(
        'A dashboard that monitors Kubernetes Events and focuses on giving a overview for events. A pre requisite is configuring Loki, Alloy and Prometheus - it is described in this blog post: https://hodovi.cc/blog/kubernetes-events-monitoring-with-loki-alloy-and-grafana/. %s' % mixinUtils.dashboards.dashboardDescriptionLink('kubernetes-events-mixin', 'https://github.com/adinhodovic/kubernetes-events-mixin')
      ) +
      dashboard.withUid($._config.dashboardIds[dashboardName]) +
      dashboard.withTags($._config.tags) +
      dashboard.withTimezone('utc') +
      dashboard.withEditable(false) +
      dashboard.time.withFrom('now-3h') +
      dashboard.time.withTo('now') +
      dashboard.withVariables(variables) +
      dashboard.withLinks(
        mixinUtils.dashboards.dashboardLinks('Kubernetes Events', $._config)
      ) +
      dashboard.withPanels(
        rows
      ) +
      dashboard.withAnnotations(
        mixinUtils.dashboards.annotations($._config, defaultFilters)
      ),
  },
}
