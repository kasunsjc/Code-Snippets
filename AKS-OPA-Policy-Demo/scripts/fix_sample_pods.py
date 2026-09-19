import yaml, glob

RUNASUSER_FILES = {
    "sample-apps/bad-pod-capabilities.yaml",
    "sample-apps/bad-pod-host-network.yaml",
    "sample-apps/bad-pod-host-port.yaml",
    "sample-apps/bad-pod-latest-tag.yaml",
    "sample-apps/bad-pod-no-probes.yaml",
    "sample-apps/good-pod.yaml",
}

def process_container(c):
    changed = False
    sc = c.get("securityContext", {})
    if sc.get("readOnlyRootFilesystem") is True:
        vm = c.setdefault("volumeMounts", [])
        names = {m.get("name") for m in vm}
        if "nginx-cache" not in names:
            vm.append({"name": "nginx-cache", "mountPath": "/var/cache/nginx"})
            changed = True
        if "nginx-run" not in names:
            vm.append({"name": "nginx-run", "mountPath": "/var/run"})
            changed = True
    res = c.get("resources", {}).get("limits")
    if res:
        if res.get("cpu") == "500m":
            res["cpu"] = "100m"
            changed = True
        if res.get("memory") == "512Mi":
            res["memory"] = "128Mi"
            changed = True
    return changed

def process_pod(doc, path):
    if not doc or doc.get("kind") != "Pod":
        return False
    changed = False
    spec = doc["spec"]
    any_readonly = False
    for c in spec.get("containers", []):
        if process_container(c):
            changed = True
        if c.get("securityContext", {}).get("readOnlyRootFilesystem") is True:
            any_readonly = True
    if any_readonly:
        vols = spec.setdefault("volumes", [])
        names = {v.get("name") for v in vols}
        if "nginx-cache" not in names:
            vols.append({"name": "nginx-cache", "emptyDir": {}})
            changed = True
        if "nginx-run" not in names:
            vols.append({"name": "nginx-run", "emptyDir": {}})
            changed = True
    if path in RUNASUSER_FILES:
        pod_sc = spec.get("securityContext", {})
        if pod_sc.get("runAsNonRoot") is True and "runAsUser" not in pod_sc:
            pod_sc["runAsUser"] = 101
            changed = True
    return changed

for path in sorted(glob.glob("sample-apps/*.yaml")):
    with open(path) as f:
        raw = f.read()
    lines = raw.splitlines(keepends=True)
    header_lines = []
    idx = 0
    while idx < len(lines) and (lines[idx].startswith("#") or lines[idx].strip() == ""):
        header_lines.append(lines[idx])
        idx += 1
    body = "".join(lines[idx:])
    docs = list(yaml.safe_load_all(body))
    any_changed = False
    for doc in docs:
        if process_pod(doc, path):
            any_changed = True
    if not any_changed:
        continue
    dumped = yaml.safe_dump_all([d for d in docs if d is not None], sort_keys=False, default_flow_style=False)
    with open(path, "w") as f:
        f.write("".join(header_lines))
        f.write(dumped)
    print(f"updated: {path}")
