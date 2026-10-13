#!/usr/bin/env bash
set -euo pipefail
tool="$(basename "$0")"
printf '%s %s\n' "$tool" "$*" >> "$MOCK_LOG"

case "$tool" in
  terraform)
    if [[ "$*" == *"output -raw"* ]]; then
      for argument in "$@"; do
        last_argument="$argument"
      done
      case "$last_argument" in
        subscription_id) echo "00000000-0000-0000-0000-000000000002" ;;
        resource_group_name) echo rg-gha-runners-dev ;;
        node_resource_group_name) echo rg-gha-runners-dev-nodes ;;
        aks_cluster_name) echo aks-gha-runners-dev ;;
        portal_url) echo https://portal.azure.com/ ;;
        *) exit 1 ;;
      esac
    elif [[ "$*" == *"destroy"* ]]; then
      [[ "${MOCK_DESTROY_FAIL:-0}" == "0" ]] || exit 1
      touch "$MOCK_DESTROYED"
    fi
    ;;
  az)
    case "$1 $2" in
      "account show")
        [[ "$*" != *"--query id"* ]] || echo "00000000-0000-0000-0000-000000000002"
        ;;
      "group exists")
        if [[ "${MOCK_GROUP_LEFT:-0}" == "1" ]]; then
          echo true
        elif [[ -f "$MOCK_DESTROYED" || "${MOCK_CLUSTER_GONE:-0}" == "1" ]]; then
          echo false
        else
          echo true
        fi
        ;;
      "aks list") echo 1 ;;
      "aks get-credentials") mkdir -p "$(dirname "$KUBECONFIG")"; touch "$KUBECONFIG" ;;
      *) exit 1 ;;
    esac
    ;;
  kubectl)
    if [[ "$1" == "auth" ]]; then
      echo yes
    elif [[ "$1 $2" == "get pods" ]]; then
      [[ "$*" == *"--namespace arc-systems"* ]] || exit 1
      echo pod/demo-listener
    elif [[ "$1 $2" == "create secret" ]]; then
      for argument in "$@"; do
        case "$argument" in
          --from-file=github_token=*)
            [[ "$(cat "${argument#--from-file=github_token=}")" == "test-token-not-a-real-credential" ]] || exit 1
            ;;
          --from-file=github_app_id=*)
            [[ "$(cat "${argument#--from-file=github_app_id=}")" == "123456" ]] || exit 1
            ;;
          --from-file=github_app_installation_id=*)
            [[ "$(cat "${argument#--from-file=github_app_installation_id=}")" == "654321" ]] || exit 1
            ;;
          --from-file=github_app_private_key=*)
            [[ -r "${argument#--from-file=github_app_private_key=}" ]] || exit 1
            ;;
        esac
      done
      printf 'apiVersion: v1\nkind: Secret\n'
    elif [[ "$1" == "apply" ]]; then
      [[ "$*" != *"-f -"* ]] || cat >/dev/null
    elif [[ "$1" == "wait" ]]; then
      [[ "$*" == *"--namespace arc-systems"* ]] || exit 1
    fi
    ;;
  helm)
    [[ "$1" != "list" ]] || echo '[{"name":"installed"}]'
    ;;
  kubelogin|openssl|sleep) ;;
  *) exit 1 ;;
esac
