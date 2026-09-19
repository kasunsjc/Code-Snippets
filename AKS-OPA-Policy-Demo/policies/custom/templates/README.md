# OPA ConstraintTemplate anatomy

Every file in this folder is a Kubernetes **CustomResourceDefinition (CRD)**
manifest of kind `ConstraintTemplate` (`templates.gatekeeper.sh/v1`). This is
the exact same YAML you would `kubectl apply` directly to a cluster running
[Gatekeeper](https://open-policy-agent.github.io/gatekeeper/website/) - the
only difference here is that instead of applying it with `kubectl`, we base64
it and hand it to Azure Policy via `policyRule.then.details.templateInfo`, and
Azure Policy applies it to the cluster for us as part of assigning the policy.

```yaml
apiVersion: templates.gatekeeper.sh/v1   # ConstraintTemplate API version
kind: ConstraintTemplate
metadata:
  name: k8sdenydefaultnamespace          # lowercase, no spaces - becomes part of the CRD name
  annotations:
    metadata.gatekeeper.sh/title: "..."  # human-friendly title (optional)
    description: >-                      # what the constraint enforces (optional)
      ...
spec:
  crd:
    spec:
      names:
        kind: K8sDenyDefaultNamespace     # the Kind of the Constraint CR this template generates
                                          # (PascalCase, must be unique on the cluster)
      validation:
        # openAPIV3Schema defines the shape of `spec.parameters` on any
        # Constraint created from this template - i.e. what you're allowed
        # to put in the Azure Policy assignment's "values" block.
        openAPIV3Schema:
          type: object
          properties:
            exemptImages:
              type: array
              items:
                type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8sdenydefaultnamespace   # must match `target`'s expected package name

        # `violation` is the rule Gatekeeper evaluates on every admission
        # request. Each result becomes one compliance/deny message.
        violation[{"msg": msg}] {
          input.review.object.metadata.namespace == "default"
          msg := sprintf("...: %v", [input.review.object.metadata.name])
        }
      libs:
        # optional shared Rego packages, imported from the main rego via
        # `import data.lib.<package>` - used to de-duplicate helper logic
        # (e.g. "is this an UPDATE request", "is this image exempt") across
        # multiple ConstraintTemplates.
        - |
          package lib.some_helper
          ...
```

## Field reference

| Field | Purpose |
| --- | --- |
| `metadata.name` | Name of the ConstraintTemplate CRD (lowercase). |
| `spec.crd.spec.names.kind` | The Kind of the `Constraint` custom resource this template produces. Referenced by Azure Policy only indirectly - Azure creates a `Constraint` of this `Kind` automatically from your policy assignment's parameters. |
| `spec.crd.spec.validation.openAPIV3Schema` | JSON-schema-style definition of the parameters your policy can accept (`spec.parameters` on the Constraint). Each property here should have a matching entry in the Azure Policy definition's `parameters` block and be wired through `policyRule.then.details.values`. |
| `spec.targets[].target` | Always `admission.k8s.gatekeeper.sh` for Kubernetes admission control. |
| `spec.targets[].rego` | The actual [Rego](https://www.openpolicyagent.org/docs/latest/policy-language/) policy logic. Must define a `violation` rule/set; every entry produced is one admission-time complaint. |
| `spec.targets[].libs` | Optional shared Rego packages the main `rego` block imports via `import data.lib.<name>`. |

## How this maps into an Azure Policy JSON definition

The whole YAML file above is base64-encoded and placed at:

```json
"policyRule": {
  "then": {
    "details": {
      "templateInfo": {
        "sourceType": "Base64Encoded",
        "content": "<base64 of the ConstraintTemplate YAML>"
      },
      "apiGroups": [""],
      "kinds": ["Pod"],
      "values": { "exemptImages": "[parameters('exemptImages')]" }
    }
  }
}
```

`values` maps each Azure Policy parameter to the matching property under
`spec.crd.spec.validation.openAPIV3Schema.properties` - these become
`input.parameters.<name>` inside the Rego.

## Source of the Rego in this demo

Seven of the ConstraintTemplates here are copied verbatim (Rego logic
unchanged) from the official, community-maintained
[open-policy-agent/gatekeeper-library](https://github.com/open-policy-agent/gatekeeper-library)
so the policy logic is well-tested and widely used in production:

| File | Library source |
| --- | --- |
| `deny-privileged-containers.yaml` | `library/pod-security-policy/privileged-containers` |
| `deny-host-namespaces.yaml` | `library/pod-security-policy/host-namespaces` |
| `deny-privilege-escalation.yaml` | `library/pod-security-policy/allow-privilege-escalation` |
| `require-readonly-root-fs.yaml` | `library/pod-security-policy/read-only-root-filesystem` |
| `require-resource-limits.yaml` | `library/general/containerlimits` |
| `allowed-repos.yaml` | `library/general/allowedrepos` |
| `require-team-labels.yaml` | `library/general/requiredlabels` |

The following templates are fully self-authored here to demonstrate writing
your own Rego from scratch:

- `deny-default-namespace.yaml`
- `require-non-root.yaml`
- `require-seccomp-runtime-default.yaml`
- `drop-all-capabilities.yaml`
- `deny-host-network.yaml`
- `deny-latest-image-tags.yaml`
- `require-probes.yaml`
- `deny-host-ports.yaml`

Unlike the earlier version of this demo, none of the Azure Policy definitions
reference these templates by public URL (`sourceType: PublicURL`) - every one
is embedded via `sourceType: Base64Encoded`, so `deploy.sh` has **no runtime
dependency on GitHub or any external template host**.

## Policy-by-policy Rego walkthrough

Every template follows the same evaluation model:

1. Gatekeeper receives a Kubernetes `AdmissionReview` in `input.review`.
2. The Azure Policy add-on creates a Constraint from the template and passes
   assignment values through `input.parameters`.
3. Rego evaluates the object under `input.review.object`.
4. Each item emitted by `violation` becomes an audit result and, when the
   Azure Policy effect is `deny`, an admission rejection.

The policy-specific logic in this demo works as follows.

### `deny-privileged-containers`

The Rego iterates through `spec.containers`, `spec.initContainers`, and
`spec.ephemeralContainers`. It reads `container.securityContext.privileged` and
emits a violation when it is true. The shared `lib.exempt_container` helper
allows an image to be excluded by exact match or by a prefix ending in `*`.

### `deny-host-namespaces`

The template reads `spec.hostPID` and `spec.hostIPC` from the Pod. If either
field is true, the Pod is sharing a host namespace and Rego emits a violation.
The template also uses `lib.exclude_update` because these fields are
immutable after creation; the policy evaluates the initial create rather than
producing a misleading update violation.

### `deny-privilege-escalation`

For every container, Rego requires
`securityContext.allowPrivilegeEscalation == false`. A missing security
context or missing field is treated as non-compliant because omission does
not explicitly prevent escalation. Image exemptions use the shared helper.

### `require-readonly-root-fs`

For every container, Rego requires
`securityContext.readOnlyRootFilesystem == true`. Missing security context,
missing field, or `false` all produce a violation. This prevents a container
from writing to its image-backed root filesystem.

### `require-resource-limits`

The template examines CPU and memory limits for regular and init containers.
It emits violations when:

- `resources` or `resources.limits` is missing.
- CPU or memory limits are missing.
- A quantity cannot be parsed.
- CPU exceeds the configured `input.parameters.cpu` maximum.
- Memory exceeds the configured `input.parameters.memory` maximum.

The `canonify_cpu` and `canonify_mem` helper rules normalize Kubernetes
quantities such as `500m`, `1`, `512Mi`, and `1Gi` before comparing them.

### `allowed-repos`

Rego checks the image of every regular, init, and ephemeral container. The
`strings.any_prefix_match` helper compares each image against
`input.parameters.repos`. An image is compliant when it begins with one of
the configured prefixes, such as `docker.io/library/` or
`mcr.microsoft.com/`.

### `deny-default-namespace`

This is the smallest self-authored policy in the demo. It reads
`input.review.object.metadata.namespace` and emits a violation when the value
is `default`. It demonstrates that a useful custom policy can be only a few
lines of Rego when the admission object and desired rule are simple.

### `require-team-labels`

The template builds a set of labels supplied by the Pod and a set of required
labels from `input.parameters.labels`. The set difference identifies missing
labels. A second rule checks each configured `allowedRegex`, when present,
against the actual label value. The optional `input.parameters.message`
parameter lets an assignment replace the default violation text.

### `require-non-root`

Rego iterates through all container types and calculates the effective
`runAsNonRoot` and `runAsUser` values. A container-level value wins; when the
container field is absent, the rule falls back to the Pod-level
`spec.securityContext`. It requires the effective `runAsNonRoot` value to be
true and rejects an effective `runAsUser` of `0`. This prevents a container
from overriding a secure Pod-level default with a root configuration.

### `require-seccomp-runtime-default`

The template calculates the effective seccomp profile for every container.
`container.securityContext.seccompProfile` overrides the Pod-level
`spec.securityContext.seccompProfile`, so Rego checks the container profile
first and falls back to the Pod profile only when the container does not set
one. It emits a violation unless the effective profile is `RuntimeDefault`.
This specifically catches a container changing a secure Pod-level profile to
`Unconfined`.

### Pod-level versus container-level security context

Kubernetes security context and networking fields do not all have the same
scope. Some fields exist at both `spec.securityContext` (Pod) and
`container.securityContext`, where the container value wins when both are
set. Others exist at only one level, so there is nothing for a container (or
a Pod default) to override:

| Policy | Field | Exists at Pod level? | Exists at container level? | Can a container override the Pod default? |
| --- | --- | --- | --- | --- |
| `require-non-root` | `runAsNonRoot`, `runAsUser` | Yes | Yes | Yes. The Rego calculates the effective container value, falling back to the Pod value only when the container omits the field. |
| `require-seccomp-runtime-default` | `seccompProfile.type` | Yes | Yes | Yes. The container profile wins over the Pod profile. |
| `deny-privileged-containers` | `privileged` | No | Yes | Not applicable. `privileged` does not exist in `PodSecurityContext`, so there is no Pod-level default to override. |
| `deny-privilege-escalation` | `allowPrivilegeEscalation` | No | Yes | Not applicable, for the same reason as `privileged`. This is why the policy only ever needs to read `container.securityContext.allowPrivilegeEscalation`. |
| `require-readonly-root-fs` | `readOnlyRootFilesystem` | No | Yes | Not applicable. This field is container-only. |
| `drop-all-capabilities` | `capabilities.drop` | No | Yes | Not applicable. `capabilities` is container-only. |
| `deny-host-network` | `hostNetwork` | Yes (`spec.hostNetwork`) | No | Not applicable, in the other direction: there is no container-level `hostNetwork`, so only the Pod-level field needs to be checked. |
| `deny-host-namespaces` | `hostPID`, `hostIPC` | Yes | No | Not applicable, for the same reason as `hostNetwork`. |
| `deny-host-ports` | `hostPort` | No | Yes (per container port) | Not applicable. `hostPort` is set per container port; there is no Pod-level default to override, but every container must still be checked individually. |

The important rule for policy authors is to first determine **where a field
can legally be set** before writing the Rego. When a field exists at both
levels (`runAsNonRoot`, `runAsUser`, `seccompProfile`), the policy must
compute the *effective* value, because a compliant Pod-level default can be
silently overridden by a container. When a field exists at only one level
(`privileged`, `allowPrivilegeEscalation`, `readOnlyRootFilesystem`,
`capabilities`, `hostNetwork`, `hostPID`, `hostIPC`, `hostPort`), checking
that single level is already correct and complete - there is no override to
guard against.

### `drop-all-capabilities`

For every container, Rego looks for `"ALL"` in
`securityContext.capabilities.drop`. A missing capabilities block or a drop
list without `ALL` is non-compliant. This removes inherited Linux capabilities
unless a separate, explicitly reviewed policy allows an exception.

### `deny-host-network`

This policy reads `spec.hostNetwork` and emits a violation when it is true.
Unlike `deny-host-namespaces`, which checks host PID and IPC, this rule focuses
on the node's network namespace and host-level network access.

### `deny-latest-image-tags`

The template iterates through container images and uses the Rego `endswith`
function to detect the mutable `:latest` tag. The violation message includes
the Pod, namespace, container, and image so the reason is visible in Azure
Policy compliance details. Version tags or immutable digests are allowed by
this policy.

### `require-probes`

For regular and init containers, Rego requires both `livenessProbe` and
`readinessProbe`. A liveness probe lets Kubernetes restart an unhealthy
container; a readiness probe controls whether the container receives traffic.
The policy checks that the probe objects exist, while Kubernetes validates the
probe handler itself.

### `deny-host-ports`

For every regular and init container, Rego iterates through `container.ports`
and emits a violation when a port sets `hostPort` to a non-zero value.
`hostPort` binds the container port directly to that port on the node,
bypassing the Pod network and potentially conflicting with other workloads
or exposing the container outside of a Service. There is no Pod-level
`hostPort` field, so this policy only ever needs to check containers.

## Reading a violation rule

This small example captures the common Rego pattern used throughout the demo:

```rego
violation[{"msg": msg}] {
  container := input.review.object.spec.containers[_]
  not container.securityContext.readOnlyRootFilesystem == true
  msg := sprintf(
    "Pod <%v>, container <%v> must use a read-only root filesystem",
    [input.review.object.metadata.name, container.name],
  )
}
```

- `container := ...[_]` iterates over every container in the array.
- `not ... == true` treats a missing or false value as a violation.
- `msg` is the human-readable reason shown by Gatekeeper and Azure Policy.
- The rule emits nothing when the object is compliant.

This separation is intentional: the ConstraintTemplate contains reusable Rego
logic, while the Azure Policy definition supplies scope, effect, namespace
filters, and assignment parameters.
