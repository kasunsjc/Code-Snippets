# Helm values for the falco/falco chart.
# __WEBHOOK_URL__ is replaced by deploy.sh with the Logic App callback URL.
driver:
  kind: modern_ebpf

falco:
  json_output: true
  json_include_output_property: true
  log_level: info
  priority: debug
  http_output:
    enabled: false
  syslog_output:
    enabled: false
  stdout_output:
    enabled: true
  file_output:
    enabled: false

falcoctl:
  artifact:
    install:
      enabled: true
    follow:
      enabled: true
  config:
    artifact:
      install:
        refs:
          - falco-rules:3
          - falco-incubating-rules:3
      follow:
        refs:
          - falco-rules:3

# Enable falcosidekick + UI
falcosidekick:
  enabled: true
  webui:
    enabled: true
    redis:
      storageEnabled: false
  config:
    debug: false
    customfields: "cluster:falcosec-aks,environment:demo"
    webhook:
      address: "__WEBHOOK_URL__"
      minimumpriority: "debug"
      checkcert: true
