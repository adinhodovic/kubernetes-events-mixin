local g = import 'github.com/grafana/grafonnet/gen/grafonnet-latest/main.libsonnet';

local dashboard = g.dashboard;

local variable = dashboard.variable;
local datasource = variable.datasource;
local query = variable.query;
local textbox = variable.textbox;

{
  filters(config):: {
    local this = self,
    local clusterLabel = std.get(config, 'clusterLabel', 'cluster'),

    cluster: '%(clusterLabel)s=~"$cluster"' % { clusterLabel: clusterLabel },
    job: 'job=~"$job"',
    kind: 'k8s_resource_kind="$kind"',
    namespace: 'k8s_namespace_name=~"$namespace"',
    type: 'type=~"$type"',
    promType: 'type=~"$type"',
    logType: 'k8s_resource_type=~"$type"',

    // PromQL: cluster + kind + namespace + type
    default: |||
      %(cluster)s,
      %(kind)s,
      %(namespace)s,
      %(promType)s
    ||| % this,

    // LogQL stream selector: job + cluster + kind + namespace (type is a JSON field, filtered post-parse)
    logs: |||
      %(job)s,
      %(cluster)s,
      %(kind)s,
      %(namespace)s
    ||| % this,
    logsTypeFilter: '| type=~"$type"',
  },

  // Unified variables function that supports both Prometheus and Loki datasources
  // Set datasourceType: 'prometheus' or 'loki' in config
  variables(config):: {
    local this = self,
    local dsType = std.get(config, 'datasourceType', 'prometheus'),
    local isLoki = dsType == 'loki',
    local clusterLabel = std.get(config, 'clusterLabel', 'cluster'),

    local defaultFilters = $.filters(config),

    datasource:
      datasource.new(
        'datasource',
        dsType,
      ) +
      datasource.generalOptions.withLabel('Data source') +
      (
        if !isLoki then
          {
            current: {
              selected: true,
              text: config.datasourceName,
              value: config.datasourceName,
            },
          }
        else {}
      ),

    cluster:
      if isLoki then
        query.new('cluster') +
        query.withDatasourceFromVariable(this.datasource) +
        query.withSort(1) +
        query.generalOptions.withLabel('Cluster') +
        query.selectionOptions.withMulti(true) +
        query.selectionOptions.withIncludeAll(true) +
        query.refresh.onLoad() +
        query.refresh.onTime() +
        (
          if config.showMultiCluster
          then query.generalOptions.showOnDashboard.withLabelAndValue()
          else query.generalOptions.showOnDashboard.withNothing()
        ) +
        // Loki-specific query structure
        {
          query: {
            label: clusterLabel,
            stream: '{job=~"$job"}',
            type: '1',
          },
        }
      else
        query.new(
          'cluster',
          'label_values(namespace_kind_type:kubernetes_events:count1m{}, %s)' % clusterLabel,
        ) +
        query.withDatasourceFromVariable(this.datasource) +
        query.withSort(1) +
        query.generalOptions.withLabel('Cluster') +
        query.selectionOptions.withMulti(true) +
        query.selectionOptions.withIncludeAll(true) +
        query.refresh.onLoad() +
        query.refresh.onTime() +
        (
          if config.showMultiCluster
          then query.generalOptions.showOnDashboard.withLabelAndValue()
          else query.generalOptions.showOnDashboard.withNothing()
        ),

    // Loki-specific job variable
    job:
      if isLoki then
        query.new('job') +
        query.queryTypes.withLabelValues('job') +
        query.withRegex('.*events.*') +
        query.withDatasourceFromVariable(this.datasource) +
        query.withSort(1) +
        query.generalOptions.withLabel('Job') +
        query.refresh.onTime()
      else
        error 'job variable is only available for Loki datasource',

    kind:
      if isLoki then
        query.new('kind') +
        query.withDatasourceFromVariable(this.datasource) +
        query.withSort(1) +
        query.generalOptions.withLabel('Kind') +
        query.refresh.onLoad() +
        query.refresh.onTime() +
        // Loki-specific query structure
        {
          query: {
            label: 'k8s_resource_kind',
            stream: '{job=~"$job", %s=~"$cluster"}' % clusterLabel,
            type: '1',
          },
        }
      else
        query.new(
          'kind',
          'label_values(namespace_kind_type:kubernetes_events:count1m{%(cluster)s, %(type)s}, k8s_resource_kind)' % defaultFilters,
        ) +
        query.withDatasourceFromVariable(this.datasource) +
        query.withSort(1) +
        query.generalOptions.withLabel('Kind') +
        query.refresh.onLoad() +
        query.refresh.onTime(),

    namespace:
      if isLoki then
        query.new('namespace') +
        query.withDatasourceFromVariable(this.datasource) +
        query.withSort(1) +
        query.generalOptions.withLabel('Namespace') +
        query.selectionOptions.withMulti(true) +
        query.selectionOptions.withIncludeAll(true) +
        query.refresh.onLoad() +
        query.refresh.onTime() +
        // Loki-specific query structure
        {
          query: {
            label: 'k8s_namespace_name',
            stream: '{job=~"$job", %s=~"$cluster", k8s_resource_kind="$kind"}' % clusterLabel,
            type: '1',
          },
        }
      else
        query.new(
          'namespace',
          'label_values(namespace_kind_type:kubernetes_events:count1m{%(cluster)s, %(type)s, %(kind)s}, k8s_namespace_name)' % defaultFilters,
        ) +
        query.withDatasourceFromVariable(this.datasource) +
        query.withSort(1) +
        query.generalOptions.withLabel('Namespace') +
        query.selectionOptions.withMulti(true) +
        query.selectionOptions.withIncludeAll(true) +
        query.refresh.onLoad() +
        query.refresh.onTime(),

    type:
      if isLoki then
        variable.custom.new(
          'type',
          ['Normal', 'Warning'],
        ) +
        variable.custom.generalOptions.withLabel('Event Type') +
        variable.custom.selectionOptions.withMulti(true) +
        variable.custom.selectionOptions.withIncludeAll(true, '.*') +
        variable.custom.generalOptions.withCurrent('All', '$__all')
      else
        query.new(
          'type',
          'label_values(namespace_kind_type:kubernetes_events:count1m{%(cluster)s}, type)' % defaultFilters,
        ) +
        query.withDatasourceFromVariable(this.datasource) +
        query.withSort(1) +
        query.generalOptions.withLabel('Event Type') +
        query.selectionOptions.withMulti(true) +
        query.selectionOptions.withIncludeAll(true, '.*') +
        query.refresh.onLoad() +
        query.refresh.onTime(),

    // Loki-specific textbox variables
    name:
      if isLoki then
        variable.query.new('name') +
        {
          type: 'textbox',
        } +
        textbox.generalOptions.withLabel('Name') +
        textbox.generalOptions.withDescription('Name of the Kubernetes resource. Use the search, otherwise there is too many unique resources.')
      else
        error 'name variable is only available for Loki datasource',

    search:
      if isLoki then
        variable.query.new('search') +
        {
          type: 'textbox',
        } +
        textbox.generalOptions.withLabel('Search') +
        textbox.generalOptions.withDescription('Generic search of the event.')
      else
        error 'search variable is only available for Loki datasource',
  },
}
