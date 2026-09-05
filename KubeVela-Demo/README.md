# KubeVela on AKS

This demo provisions a basic AKS cluster, installs KubeVela, and deploys a small NGINX application through the KubeVela `Application` API.

## Architecture

- AKS Standard cluster with two `Standard_D2as_v5` Azure Linux nodes
- Azure CNI Overlay with Cilium data plane
- Microsoft Entra ID Azure RBAC, OIDC issuer, and workload identity
- Custom AKS node resource group: `rg-kubevela-demo-dev-nodes`
- KubeVela installed in the `vela-system` namespace

## Prerequisites

- Azure CLI authenticated to the target subscription
- Terraform 1.6 or newer
- `kubectl`, `kubelogin`, and Helm 3

## Deploy the cluster and KubeVela

```sh
./deploy.sh
```

To use a different region or name, copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars` and edit it before running the script.

## Run the sample

```sh
kubectl apply -f kubernetes-manifests/hello-kubevela.yaml
kubectl get application hello-kubevela
kubectl get deploy,service -l app.oam.dev/component=web
```

Access the application after the service receives a public IP:

```sh
kubectl get service web
```

## Clean up

```sh
kubectl delete -f kubernetes-manifests/hello-kubevela.yaml
cd terraform
terraform destroy
rm -rf .terraform terraform.tfstate terraform.tfstate.* tfplan
```