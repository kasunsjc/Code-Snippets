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

Seven of the eight ConstraintTemplates here are copied verbatim (Rego logic
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

Unlike the earlier version of this demo, none of the Azure Policy definitions
reference these templates by public URL (`sourceType: PublicURL`) - every one
is embedded via `sourceType: Base64Encoded`, so `deploy.sh` has **no runtime
dependency on GitHub or any external template host**.
