variable "kubernetes" {
  description = <<-EOT
    Connection settings for the target cluster. Certificates/keys are base64-encoded.
    Authenticate with one of: token, client_certificate + client_key, exec, or config_path.
  EOT
  type = object({
    host                   = optional(string)
    cluster_ca_certificate = optional(string)
    insecure               = optional(bool, false)
    token                  = optional(string)
    client_certificate     = optional(string)
    client_key             = optional(string)
    config_path            = optional(string)
    config_context         = optional(string)
    exec = optional(object({
      api_version = optional(string, "client.authentication.k8s.io/v1beta1")
      command     = string
      args        = optional(list(string), [])
      env         = optional(map(string), {})
    }))
  })
  sensitive = true

  validation {
    condition     = var.kubernetes.host != null || var.kubernetes.config_path != null
    error_message = "Either kubernetes.host or kubernetes.config_path must be set."
  }

  validation {
    condition = anytrue([
      var.kubernetes.token != null,
      var.kubernetes.client_certificate != null && var.kubernetes.client_key != null,
      var.kubernetes.exec != null,
      var.kubernetes.config_path != null,
    ])
    error_message = "Set one auth method: token, client_certificate + client_key, exec, or config_path."
  }
}

variable "cluster_name" {
  description = "Cilium cluster name (lowercase alphanumerics and dashes, max 32 chars)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$", var.cluster_name))
    error_message = "cluster_name must be lowercase alphanumerics/dashes, max 32 chars."
  }
}

variable "cluster_id" {
  description = "Cilium cluster ID used for meshing (integer 1-255)."
  type        = number

  validation {
    condition     = floor(var.cluster_id) == var.cluster_id && var.cluster_id >= 1 && var.cluster_id <= 255
    error_message = "cluster_id must be a whole number between 1 and 255."
  }
}

variable "cilium_version" {
  description = "Cilium Helm chart version."
  type        = string
  default     = "1.18.9"
}

variable "k8s_service_port" {
  description = "Port number for the Kubernetes API server."
  type        = number
  default     = 443
}

variable "values" {
  description = "Additional Helm values (YAML strings) merged over the defaults."
  type        = list(string)
  default     = []
}

variable "aws" {
  description = "AWS-specific settings for Cilium."
  type = object({
    region = string # is this necessary for basic bootstrapping or can we just rely on auto-discovery???
    service_account = string
  })
}
