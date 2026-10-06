locals {
  k8s = var.kubernetes

  kubeconfig = local.k8s.config_path != null ? null : yamlencode({
    apiVersion        = "v1"
    kind              = "Config"
    "current-context" = "target"
    clusters = [{
      name = "target"
      cluster = merge(
        { server = local.k8s.host },
        local.k8s.cluster_ca_certificate == null ? {} : { "certificate-authority-data" = local.k8s.cluster_ca_certificate },
        local.k8s.insecure ? { "insecure-skip-tls-verify" = true } : {},
      )
    }]
    users = [{
      name = "target"
      user = merge(
        local.k8s.token == null ? {} : { token = local.k8s.token },
        local.k8s.client_certificate == null ? {} : { "client-certificate-data" = local.k8s.client_certificate },
        local.k8s.client_key == null ? {} : { "client-key-data" = local.k8s.client_key },
        local.k8s.exec == null ? {} : {
          exec = {
            apiVersion      = local.k8s.exec.api_version
            command         = local.k8s.exec.command
            args            = local.k8s.exec.args
            env             = [for k, v in local.k8s.exec.env : { name = k, value = v }]
            interactiveMode = "Never"
          }
        },
      )
    }]
    contexts = [{ name = "target", context = { cluster = "target", user = "target" } }]
  })

  namespace = "cilium-system"

  namespace_manifest = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata   = { name = local.namespace }
  })

  host = replace(var.kubernetes.host, "https://", "")
}

data "helm_template" "cilium" {
  name         = "cilium"
  repository   = "https://helm.cilium.io"
  chart        = "cilium"
  version      = var.cilium_version
  namespace    = local.namespace
  kube_version = "1.28.0"
  include_crds = true

  values = concat([
    yamlencode({
      k8sServiceHost = local.host
      k8sServicePort = var.k8s_service_port
      cluster = {
        name = var.cluster_name
        id   = var.cluster_id
      }
      operator = {
        replicas = 2
        tolerations = [
          { operator = "Exists" } # Ensure the cilium-operator runs on some Node
        ]
      }

      # our default values
      kubeProxyReplacement = true
      forceDeviceDetection = true
      encryption = {
        enabled = true
        nodeEncryption = false
        type = "wireguard"
      }
      gatewayAPI = {
        enabled = false
      }
      hubble = {
        enabled = false # will be enabled later by ArgoCD
      }
    })
    ], var.aws == null ? [] : [
    yamlencode({
      serviceAccounts = {
        operator = {
          annotations = {
            "eks.amazonaws.com/role-arn" = var.aws.service_account
          }
        }
      }
    })
  ], var.values)
}

# Fire-once: no inputs/triggers, so it runs only on create and never touches the cluster again.
resource "terraform_data" "cilium_bootstrap" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      umask 077
      if [[ -n "$KUBECONFIG_B64" ]]; then
        KUBECONFIG="$(mktemp)"
        trap 'rm -f "$KUBECONFIG"' EXIT
        printf '%s' "$KUBECONFIG_B64" | base64 -d > "$KUBECONFIG"
      else
        KUBECONFIG="$KUBECONFIG_PATH"
      fi
      export KUBECONFIG
      printf '%s' "$MANIFEST_GZ" | base64 -d | gunzip | \
        kubectl apply --server-side --force-conflicts --field-manager=cilium-bootstrap \
          $${KUBE_CONTEXT:+--context="$KUBE_CONTEXT"} -f -
    EOT

    environment = {
      KUBECONFIG_B64  = local.kubeconfig == null ? "" : base64encode(local.kubeconfig)
      KUBECONFIG_PATH = local.k8s.config_path == null ? "" : pathexpand(local.k8s.config_path)
      KUBE_CONTEXT    = local.k8s.config_context == null ? "" : local.k8s.config_context
      # Gzipped to stay under the per-variable size limit for process environments.
      MANIFEST_GZ = base64gzip(join("\n---\n", [local.namespace_manifest, data.helm_template.cilium.manifest]))
    }
  }
}
