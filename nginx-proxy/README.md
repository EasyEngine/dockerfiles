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

For WordPress multisite with subdomain configuration, the container's `VIRTUAL_HOST` contains both `domain.com` and `*.domain.com`. The `*.domain.com` entry gets its own server block, and a single `_wildcard.` htpasswd file protects it.

#### Naming Convention

Use the `_wildcard.` prefix:

```
/etc/nginx/htpasswd/_wildcard.domain.com
```

This file applies only to hosts that literally start with `*.`, i.e. the `*.domain.com` server block (all subdomains like `blog.domain.com`, `shop.domain.com` that are served by it). It does not apply to `domain.com` itself, which uses its exact file `/etc/nginx/htpasswd/domain.com`, and it never applies to a separately configured host such as a different site on `shop.domain.com`.

There are no label-counting or multi-level TLD heuristics: `*.domain.co.in` maps to `_wildcard.domain.co.in` and `*.ms.dev.example.com` maps to `_wildcard.ms.dev.example.com`.

#### Lookup Order

For each host, the template checks for htpasswd files in this order:

1. **Exact match**: `/etc/nginx/htpasswd/<host>` (e.g. `domain.com`)
2. **Wildcard**: `/etc/nginx/htpasswd/_wildcard.<X>`, only when the host is `*.<X>`
3. **Default**: `/etc/nginx/htpasswd/default`

| Host | Files checked |
|------|---------------|
| `example.com` | `example.com`, then `default` |
| `*.example.com` | `*.example.com`, then `_wildcard.example.com`, then `default` |
| `shop.example.com` (its own `VIRTUAL_HOST`) | `shop.example.com`, then `default` |
| `*.domain.co.in` | `*.domain.co.in`, then `_wildcard.domain.co.in`, then `default` |

#### Example Setup

```bash
# Protect a WordPress subdomain multisite (VIRTUAL_HOST=example.com,*.example.com)
htpasswd -c /etc/nginx/htpasswd/example.com admin
htpasswd -c /etc/nginx/htpasswd/_wildcard.example.com admin
```

When auth is enabled, the ACL include follows the same mapping: a `*.<X>` host uses `/etc/nginx/vhost.d/_wildcard.<X>_acl` (see below).

---

## Access Control Lists (ACL)

Create ACL files to restrict access by IP:

```bash
# Per-domain ACL
/etc/nginx/vhost.d/example.com_acl

# ACL for a *.example.com host
/etc/nginx/vhost.d/_wildcard.example.com_acl

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
| `SSL_STAPLING` | Enable OCSP stapling (`on` or `off`) | `on` |
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
    # HTTP auth via /etc/nginx/htpasswd/example.com and /etc/nginx/htpasswd/_wildcard.example.com
```
