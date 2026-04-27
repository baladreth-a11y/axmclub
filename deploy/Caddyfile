# AxMclub.com — Caddy reverse proxy + automatic HTTPS
#
# 1. Replace example.com with your real apex + www below.
# 2. Install Caddy on the host:  winget install CaddyServer.Caddy
# 3. Drop this file at C:\Caddy\Caddyfile and run:
#        caddy run --config C:\Caddy\Caddyfile
#    (Or register as a Windows service via NSSM; see deploy/install-service.ps1.)
# 4. Open firewall ports 80 + 443 — Caddy will fetch the Let's Encrypt cert
#    on the first request to the domain.

# Global options: trust Cloudflare's edge IPs and read the real client IP
# from the CF-Connecting-IP header. Without this, the only IP Caddy ever
# sees is Cloudflare's. Ranges are Cloudflare's published IPs from
# https://www.cloudflare.com/ips/ (refresh occasionally; they're stable).
{
    servers {
        trusted_proxies static \
            173.245.48.0/20    103.21.244.0/22   103.22.200.0/22 \
            103.31.4.0/22      141.101.64.0/18   108.162.192.0/18 \
            190.93.240.0/20    188.114.96.0/20   197.234.240.0/22 \
            198.41.128.0/17    162.158.0.0/15    104.16.0.0/13 \
            104.24.0.0/14      172.64.0.0/13     131.0.72.0/22 \
            2400:cb00::/32     2606:4700::/32    2803:f800::/32 \
            2405:b500::/32     2405:8100::/32    2a06:98c0::/29 \
            2c0f:f248::/32
        client_ip_headers CF-Connecting-IP
    }
}

example.com, www.example.com {
    encode gzip zstd

    # Security headers — HSTS is commented out until you are SURE HTTPS
    # is stable on the domain (once enabled, browsers will refuse http:// for a year).
    header {
        # Strict-Transport-Security "max-age=31536000; includeSubDomains"
        X-Content-Type-Options        "nosniff"
        Referrer-Policy               "strict-origin-when-cross-origin"
        X-Frame-Options               "DENY"
        Permissions-Policy            "geolocation=(), microphone=(), camera=()"
        -Server
    }

    # Optional: restrict the admin panel to a fixed IP list.
    # Uncomment + fill in your office/home IPs.
    # @admin {
    #     path /admin.html /api/admin/*
    #     not remote_ip 203.0.113.10 198.51.100.22
    # }
    # respond @admin "Forbidden" 403

    # Optional rate-limit for /api/* — requires the caddy-ratelimit plugin
    # (build with: xcaddy build --with github.com/mholt/caddy-ratelimit)
    # rate_limit {
    #     zone api_per_ip {
    #         key    {remote_host}
    #         events 60
    #         window 1m
    #     }
    #     match { path /api/* }
    # }

    # Allow up to 11 MB on the model upload endpoints (the backend caps the
    # actual file at 10 MB; the extra headroom covers multipart overhead).
    @upload {
        path /api/model/photo /api/model/gallery/add
    }
    request_body @upload {
        max_size 11MB
    }

    # Long-cache uploaded model photos. Files are content-addressed by
    # gallery filename + main.<ext>; updates change the URL so cache TTL
    # can be aggressive.
    @uploadFiles {
        path /uploads/*
    }
    header @uploadFiles {
        Cache-Control "public, max-age=86400"
    }

    reverse_proxy *********:8080 {
        header_up X-Real-IP        {remote_host}
        header_up X-Forwarded-For  {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }

    log {
        output file C:\Caddy\logs\axmclub.log {
            roll_size 10MiB
            roll_keep  7
        }
        format console
    }
}
