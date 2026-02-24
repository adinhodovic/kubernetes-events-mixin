{
  prometheusRules+:: {
    groups+: [
      {
        name: 'kubernetes-events.rules',
        interval: '1m',
        rules: [
          {
            record: 'namespace_kind_type:kubernetes_events:count1m',
            expr: |||
              sum (count_over_time({%(kubernetesEventsSelector)s} | json [1m])) by (%(clusterLabel)s, k8s_namespace_name, k8s_resource_kind, type)
            ||| % $._config,
          },
        ],
      },
    ],
  },
}
