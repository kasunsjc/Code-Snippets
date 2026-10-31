# AKS Azure Monitor Traces

Explore distributed traces from an AKS application with Azure Monitor traces (preview).

## Region availability

Azure Monitor traces (preview) currently supports Azure Monitor workspaces in only these regions:

| Azure Monitor workspace location | Azure region |
|---|---|
| `newzealandnorth` | New Zealand North |
| `westeurope` | West Europe |
| `eastus2` | East US 2 |

**North Europe (`northeurope`) isn't supported for the Azure Monitor workspace.** North Europe is included in the separate Application Insights supported-region list, but that doesn't make a North Europe Azure Monitor workspace eligible. For a new setup, use West Europe for both resources. Existing workspaces can't be moved; create a new one in a supported region.

The region list is from Microsoft's [Azure Monitor traces overview](https://learn.microsoft.com/en-us/azure/azure-monitor/app/traces-overview). Preview features aren't covered by an SLA and aren't recommended for production workloads.

## Prerequisites

- An Azure subscription and an AKS cluster in Azure public cloud.
- The [KubePlay sample app](https://github.com/kasunsjc/k8s-demo-sample-app) deployed to the `kubeplay` namespace. Follow its [AKS instructions](https://github.com/kasunsjc/k8s-demo-sample-app#aks).
- Azure CLI 2.86.0 or later and the `aks-preview` extension.
- Permission to configure AKS monitoring and Application Insights.

## Set up traces

1. **Prepare the cluster for application monitoring.** Register the `AzureMonitorAppMonitoringPreview` feature for the subscription hosting AKS, register the `Microsoft.ContainerService` provider, and enable both **Enable support for Autoinstrumentation** and **Enable support for data collection from vendor neutral OpenTelemetry SDKs (Preview)** in the AKS **Monitor** settings. See Microsoft's [AKS OTLP monitoring guide](https://learn.microsoft.com/en-us/azure/azure-monitor/containers/kubernetes-open-protocol) for the current preview registration and setup steps.
2. **Create an OTLP-enabled Application Insights resource.** In the Azure portal, enable **OTLP Support** and **Use managed workspaces**. Use West Europe for the resource and its managed workspace, the closest supported option to North Europe.
3. **Onboard the app.** Configure an `Instrumentation` custom resource for the `kubeplay` namespace and add the `instrumentation.opentelemetry.io/inject-nodejs` annotation to the `ui-gateway` pod template. Follow Microsoft's per-deployment onboarding steps below. KubePlay is a mixed-language app, so don't apply Node.js instrumentation to every deployment in the namespace.
4. **Restart the instrumented deployment** and generate requests through the app UI. The UI gateway is Node.js, and AKS injects OpenTelemetry instrumentation without changing the app source. No application-repository PR is needed for this gateway-only demo.
5. **Enable Azure Monitor traces.** Open the Application Insights resource, select **Monitoring > Traces**, and link it to an Azure Monitor workspace in `newzealandnorth`, `westeurope`, or `eastus2`. Open **Traces** from that workspace and search a time range that includes your test requests.

For the `Instrumentation` custom resource, use Microsoft's [per-deployment onboarding instructions](https://learn.microsoft.com/en-us/azure/azure-monitor/containers/kubernetes-codeless#per-deployment-onboarding). Put the annotation on the `ui-gateway` pod template and restart its deployment. Keep the Application Insights connection string out of committed manifests.

## Scope and limitations

The sample app's Node.js gateway can be autoinstrumented without a source change. This gives the demo a low-friction way to generate traces and HTTP dependency spans. It does **not** add server spans to the Python or Go services. To demonstrate a complete end-to-end trace across those services, instrument their code with OpenTelemetry and propagate trace context; that requires changes in the [sample-app repository](https://github.com/kasunsjc/k8s-demo-sample-app). Python autoinstrumentation is a separate limited preview, and Go requires code instrumentation.

Azure Monitor traces and AKS application monitoring are preview features. Confirm current prerequisites and region availability in the linked Microsoft documentation before deploying, because preview support can change.
