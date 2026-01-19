# SearXNG zeropoint Module

SearXNG is a privacy-respecting metasearch engine that aggregates results from multiple search engines. This zeropoint module lets you easily deploy SearXNG in Zeropoint OS with customizable settings via Terraform variables.

## Features

✅ **Privacy-First Metasearch** - Aggregates Google, DuckDuckGo, StartPage, Wikipedia, and more  
✅ **Easy Configuration** - Customize instance name, safe search level, autocomplete, engine list  
✅ **Multiple Formats** - JSON/HTML/RSS outputs for flexible use  
✅ **Zeropoint Ready** - Works out of the box with sensible defaults  
✅ **OpenWebUI Compatible** - Integrates with OpenWebUI for web search  
✅ **Just Works** - Zero configuration needed if you want defaults


## How It Works

- **Docker Image**: Official SearXNG image with local build
- **Settings**: Generated from Terraform vars at runtime (not baked into image)
- **Storage**: Persistent cache at `${zp_module_storage}/searxng`
- **Network**: Docker bridge network with internal DNS discovery
- **Port**: 8080 (accessible from other containers)


## Quick Start

### Via zeropoint API

```bash
curl -X POST http://<zeropoint-node>:2370/modules/install \
  -H "Content-Type: application/json" \
  -d '{
    "source": "https://github.com/zeropoint-os/searxng.git",
    "module_id": "searxng",
    "arch": "arm64"
  }'
```

### Manual Testing

```bash
# Create Docker network
docker network create zpm-test-nw

# Apply Terraform
terraform apply -var='zp_network_name=zpm-test-nw' \
  -var='zp_module_storage='$(pwd)'/data' -auto-approve

# Test search
curl 'http://172.19.0.2:8080/search?q=kubernetes&format=json'

# View results
./test-searxng.sh
```

## Input Variables

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `zp_module_id` | string | `"searxng"` | Module instance identifier |
| `zp_network_name` | string | (required) | Docker network name (injected by zeropoint) |
| `zp_arch` | string | `"amd64"` | Target architecture: amd64, arm64, etc. (injected by zeropoint) |
| `zp_module_storage` | string | (required) | Host path for persistent storage (injected by zeropoint) |
| `instance_name` | string | `"Zeropoint Search"` | Name displayed in SearXNG UI |
| `safe_search` | number | `0` | Safe search level: 0 (off), 1 (moderate), 2 (strict) |
| `autocomplete` | string | `"duckduckgo"` | Autocomplete engine: `duckduckgo`, `google`, `bing`, or empty to disable |
| `request_timeout` | number | `2.0` | Request timeout in seconds for outgoing searches |
| `enable_bot_detection` | bool | `false` | Enable/disable bot detection (usually disabled for homelab) |
| `enabled_engines` | list(string) | `["google", "duckduckgo", "wikipedia", "bing", "startpage", "qwant", "arch linux wiki", "github", "stackoverflow", "arxiv"]` | Search engines to enable by default |

## Output Values

| Name | Description |
|------|-------------|
| `main` | Docker container resource for SearXNG |
| `main_ports` | Service port definitions |
| `searxng_base_url` | Base URL accessible via Docker DNS: `http://searxng-main:8080` |
| `searxng_query_url` | Query URL for integration: `http://searxng-main:8080/search?q=<query>` |

## Configuration Details

### Settings Generation

Settings are **generated at runtime** from `settings.tpl` using Terraform `templatefile()` function:

```hcl
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
}
```

The generated settings file is **bind-mounted** into the container at `/etc/searxng/settings.yml`.

### Search Results

SearXNG aggregates results from enabled engines:

- **Google** - General web search (large index)
- **DuckDuckGo** - Privacy-focused alternative
- **Wikipedia** - Encyclopedic results
- **StartPage** - Privacy metasearch
- **Qwant** - European search engine
- **Arch Linux Wiki** - Linux documentation
- Additional engines configurable via `enabled_engines` variable

### Network Configuration

- **Mode**: Direct network access (no proxy headers needed)
- **public_instance**: `false` - Uses socket peer address
- **trusted_proxies**: `[]` - Empty for direct Docker network access
- **limiter**: `false` - Bot detection disabled for homelab

## Access & Integration

### Service Discovery (Docker DNS)

Other containers can access SearXNG via DNS:

```bash
curl http://searxng-main:8080/search?q=example
```

### OpenWebUI Integration

Pass the `searxng_query_url` output to OpenWebUI for RAG-based web search:

```hcl
module "openwebui" {
  source = "..."
  
  searxng_url = module.searxng.searxng_query_url
}
```

OpenWebUI can then fetch web search results by querying:

```
http://searxng-main:8080/search?q=<user-query>&format=json
```

### JSON API

Search via JSON API:

```bash
curl 'http://searxng-main:8080/search?q=kubernetes&format=json' | jq '.results'
```

Response includes:

```json
{
  "results": [
    {
      "title": "Kubernetes Documentation",
      "url": "https://kubernetes.io/",
      "engine": "google",
      "score": 4.5
    }
    // ... more results from different engines
  ]
}
```

## Testing

The module includes `test-searxng.sh` for validation:

```bash
./test-searxng.sh
```

Checks:
- ✓ Container is running
- ✓ HTTP endpoint responds
- ✓ Search functionality works
- ✓ JSON API returns results


## Storage

- **Config**: `${zp_module_storage}/searxng-config/` - Generated settings.yml
- **Cache**: `${zp_module_storage}/searxng/` - Search results cache and persistent data

## Customization Examples

### Strict Safe Search

```bash
terraform apply \
  -var='safe_search=2' \
  -var='zp_module_storage=./data'
```

### Custom Instance Name

```bash
terraform apply \
  -var='instance_name=My Company Search' \
  -var='zp_module_storage=./data'
```

### Specific Engines Only

```bash
terraform apply \
  -var='enabled_engines=["google","duckduckgo","wikipedia"]' \
  -var='zp_module_storage=./data'
```

## Troubleshooting

### No search results

Check that `search.formats` includes `json` in settings.yml

### Slow searches

Increase `request_timeout` variable if searches timeout (default 2 seconds)

### Bot detection issues

Keep `enable_bot_detection=false` (default) for Zeropoint OS use



## Requirements

- Terraform >= 1.0
- Docker provider ~> 3.0
- Local provider ~> 2.0

## License

Same as SearXNG (AGPL-3.0)

