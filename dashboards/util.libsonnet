local g = import 'github.com/grafana/grafonnet/gen/grafonnet-latest/main.libsonnet';

local dashboard = g.dashboard;

local variable = dashboard.variable;
local datasource = variable.datasource;
local query = variable.query;
local textbox = variable.textbox;

{
  filters(config):: {
    local this = self,
    kind: 'k8s_resource_kind="$kind"',
    namespace: 'k8s_namespace_name="$namespace"',

    default: |||
      %(kind)s,
      %(namespace)s
    ||| % this,
  },

  // Unified variables function that supports both Prometheus and Loki datasources
  // Set datasourceType: 'prometheus' or 'loki' in config
  variables(config):: {
    local this = self,
    local dsType = std.get(config, 'datasourceType', 'prometheus'),
    local isLoki = dsType == 'loki',

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
            stream: '{job=~"$job"}',
            type: '1',
          },
        }
      else
        query.new(
          'kind',
          'label_values(namespace_kind_type:kubernetes_events:count1m{}, k8s_resource_kind)' % config,
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
        query.refresh.onLoad() +
        query.refresh.onTime() +
        // Loki-specific query structure
        {
          query: {
            label: 'k8s_namespace_name',
            stream: '{job=~"$job", k8s_resource_kind="$kind"}',
            type: '1',
          },
        }
      else
        query.new(
          'namespace',
          'label_values(namespace_kind_type:kubernetes_events:count1m{k8s_resource_kind="$kind"}, k8s_namespace_name)' % config,
        ) +
        query.withDatasourceFromVariable(this.datasource) +
        query.withSort(1) +
        query.generalOptions.withLabel('Namespace') +
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
