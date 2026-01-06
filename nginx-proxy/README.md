# Nginx Proxy

A custom nginx-proxy image based on [jwilder/nginx-proxy](https://github.com/nginx-proxy/nginx-proxy) with additional features for WordPress and EasyEngine environments.

## Features

- Automatic reverse proxy configuration via Docker container labels
- SSL/TLS support with automatic certificate detection
- HTTP Basic Authentication support
- Wildcard HTTP Auth for WordPress Multisite
- Custom vhost configurations
- Access Control Lists (ACL)

---

## HTTP Basic Authentication

### Standard Authentication

Create htpasswd files in `/etc/nginx/htpasswd/` to enable HTTP auth:

```bash
# For a specific domain
htpasswd -c /etc/nginx/htpasswd/example.com username

# Default auth for all sites without specific htpasswd
htpasswd -c /etc/nginx/htpasswd/default username
```

### Wildcard Authentication (WordPress Multisite)

For WordPress multisite with subdomain configuration, you can use a single htpasswd file to protect both the main domain and all subdomains.

#### Naming Convention

Use the `_wildcard.` prefix:

```
/etc/nginx/htpasswd/_wildcard.domain.com
```

This file will apply HTTP auth to:
- `domain.com` (main domain)
- `*.domain.com` (all subdomains like `blog.domain.com`, `shop.domain.com`, etc.)

#### Lookup Order

The template checks for htpasswd files in this order:

1. **Exact match**: `/etc/nginx/htpasswd/blog.domain.com`
2. **Wildcard (3 parts)**: `/etc/nginx/htpasswd/_wildcard.domain.com` (for multi-level TLD support)
3. **Wildcard (2 parts)**: `/etc/nginx/htpasswd/_wildcard.com` (fallback)
4. **Default**: `/etc/nginx/htpasswd/default`

#### Example Setup

```bash
# Create wildcard htpasswd for WordPress multisite
htpasswd -c /etc/nginx/htpasswd/_wildcard.example.com admin

# Optional: Override for a specific subdomain
htpasswd -c /etc/nginx/htpasswd/api.example.com api_user
```

#### Multi-level TLDs

Multi-level TLDs (e.g., `.co.in`, `.com.au`) are fully supported. The template checks progressively:

1. **Last 3 parts first**: `_wildcard.domain.co.in` for `blog.domain.co.in`
2. **Then last 2 parts**: `_wildcard.co.in` as fallback

```bash
# For domain.co.in multisite
htpasswd -c /etc/nginx/htpasswd/_wildcard.domain.co.in admin

# This will protect:
# - domain.co.in
# - blog.domain.co.in
# - shop.domain.co.in
# - etc.
```

---

## Access Control Lists (ACL)

Create ACL files to restrict access by IP:

```bash
# Per-domain ACL
/etc/nginx/vhost.d/example.com_acl

# Default ACL for all sites
/etc/nginx/vhost.d/default_acl
```

Example ACL content:
```nginx
allow 192.168.1.0/24;
allow 10.0.0.0/8;
deny all;
```

---

## Custom Vhost Configuration

### Per-domain configuration

```bash
# Main vhost config
/etc/nginx/vhost.d/example.com

# Location-specific config
/etc/nginx/vhost.d/example.com_location
```

### Default configuration

```bash
/etc/nginx/vhost.d/default
/etc/nginx/vhost.d/default_location
```

---

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `VIRTUAL_HOST` | Comma-separated list of domains | - |
| `VIRTUAL_PORT` | Port to proxy to | `80` |
| `VIRTUAL_PROTO` | Protocol (`http`, `https`, `uwsgi`, `fastcgi`) | `http` |
| `HTTPS_METHOD` | `redirect`, `noredirect`, `nohttps` | `redirect` |
| `SSL_POLICY` | SSL/TLS policy | `Mozilla-Modern` |
| `HSTS` | HSTS header value | `max-age=31536000` |
| `CERT_NAME` | Custom certificate name | auto-detected |
| `NETWORK_ACCESS` | `external` or `internal` | `external` |

---

## Docker Compose Example

```yaml
services:
  nginx-proxy:
    image: your-nginx-proxy-image
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/tmp/docker.sock:ro
      - ./certs:/etc/nginx/certs:ro
      - ./htpasswd:/etc/nginx/htpasswd:ro
      - ./vhost.d:/etc/nginx/vhost.d:ro

  wordpress-multisite:
    image: wordpress
    environment:
      - VIRTUAL_HOST=example.com,*.example.com
    # HTTP auth via /etc/nginx/htpasswd/_wildcard.example.com
```
