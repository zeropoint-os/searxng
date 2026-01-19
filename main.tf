terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

variable "zp_module_id" {
  type        = string
  default     = "searxng"
  description = "Unique identifier for this module instance (user-defined, freeform)"
}

 variable "zp_network_name" {
  type        = string
  description = "Pre-created Docker network name for this module (managed by zeropoint)"
}

variable "zp_arch" {
  type        = string
  default     = "amd64"
  description = "Target architecture - amd64, arm64, etc. (injected by zeropoint)"
}

variable "zp_gpu_vendor" {
  type        = string
  default     = ""
  description = "GPU vendor (not used by SearXNG, kept for compatibility)"
}

variable "zp_module_storage" {
  type        = string
  description = "Host path for persistent storage (injected by zeropoint)"
}

variable "instance_name" {
  type        = string
  default     = "Zeropoint Search"
  description = "SearXNG instance name displayed in the UI"
}

variable "safe_search" {
  type        = number
  default     = 0
  description = "Safe search level: 0 (off), 1 (moderate), 2 (strict)"
  
  validation {
    condition     = contains([0, 1, 2], var.safe_search)
    error_message = "safe_search must be 0, 1, or 2."
  }
}

variable "request_timeout" {
  type        = number
  default     = 2.0
  description = "Request timeout in seconds for outgoing requests"
}

variable "autocomplete" {
  type        = string
  default     = "duckduckgo"
  description = "Autocomplete engine: duckduckgo, google, bing, or empty for disabled"
}

variable "enable_bot_detection" {
  type        = bool
  default     = false
  description = "Enable/disable bot detection (usually disabled for internal use)"
}

variable "enabled_engines" {
  type        = list(string)
  default     = ["google", "duckduckgo", "wikipedia", "bing", "startpage", "qwant", "arch linux wiki", "github", "stackoverflow", "arxiv"]
  description = "List of search engines to enable by default"
}

# Create storage directories for persistent data and config
resource "null_resource" "create_storage_dir" {
  provisioner "local-exec" {
    command = "mkdir -p ${var.zp_module_storage}/searxng-config ${var.zp_module_storage}/searxng"
  }
}

# Generate SearXNG settings.yml from Terraform variables
resource "local_file" "searxng_settings" {
  filename = "${var.zp_module_storage}/searxng-config/settings.yml"
  
  content = templatefile("${path.module}/settings.tpl", {
    instance_name        = var.instance_name
    safe_search          = var.safe_search
    autocomplete         = var.autocomplete
    request_timeout      = var.request_timeout
    enable_bot_detection = var.enable_bot_detection
    enabled_engines      = var.enabled_engines
  })
  
  depends_on = [null_resource.create_storage_dir]
}

# Build SearXNG image from local Dockerfile
resource "docker_image" "searxng" {
  name = "${var.zp_module_id}:latest"
  build {
    context    = path.module
    dockerfile = "Dockerfile"
    platform   = "linux/${var.zp_arch}"  # Uses injected zp_arch variable
  }
  keep_locally = true
}

# Main SearXNG container (no host port binding)
resource "docker_container" "searxng_main" {
  name  = "${var.zp_module_id}-main"
  image = docker_image.searxng.image_id

  # Network configuration (provided by zeropoint)
  networks_advanced {
    name = var.zp_network_name
  }

  # Restart policy
  restart = "unless-stopped"

  # Environment variables
  env = [
    "INSTANCE_NAME=${var.instance_name}",
    "SEARXNG_BIND_ADDRESS=0.0.0.0",
    "SEARXNG_PORT=8080",
  ]

  # SearXNG configuration (generated from template)
  volumes {
    host_path      = local_file.searxng_settings.filename
    container_path = "/etc/searxng/settings.yml"
  }

  # Persistent storage for search cache and other data
  volumes {
    host_path      = "${var.zp_module_storage}/searxng"
    container_path = "/var/lib/searxng"
  }

  # Ports exposed internally (no host binding)
  # Port 8080 is accessible via service discovery (DNS)
  
  depends_on = [local_file.searxng_settings]
}

# Outputs for zeropoint (container resource only)
output "main" {
  value       = docker_container.searxng_main
  description = "Main SearXNG container"
}

# Service ports for external access (defined but not bound to host)
output "main_ports" {
  value = {
    api = {
      port        = 8080                    # SearXNG API port
      protocol    = "http"                  # The protocol used
      transport   = "tcp"                   # Transport layer
      description = "SearXNG API endpoint"  # Description of the port
      default     = true                    # Default port for the service
    }
  }
  description = "Service ports for external access"
}

# SearXNG base URL for easy consumption by other modules
output "searxng_base_url" {
  value       = "http://${docker_container.searxng_main.name}:8080"
  description = "SearXNG base URL accessible via Docker network"
}

# SearXNG query URL for OpenWebUI RAG web search integration
output "searxng_query_url" {
  value       = "http://${docker_container.searxng_main.name}:8080/search?q=<query>"
  description = "SearXNG query URL for web search integration"
}