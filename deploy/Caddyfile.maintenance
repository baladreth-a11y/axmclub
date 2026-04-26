# AxMclub.com — MAINTENANCE MODE
#
# This Caddyfile serves a static maintenance page to everyone EXCEPT
# operators on an allow-list. The allow-list lets you keep using the
# real site (to verify a fix, deploy a change, etc.) while the public
# sees the maintenance page.
#
# To use: the enable-maintenance.ps1 script copies this file to
# C:\Caddy\Caddyfile (replacing the live one), then restarts Caddy.
# disable-maintenance.ps1 swaps it back.

# Global options: trust Cloudflare's edge IPs and read the real client IP
# from CF-Connecting-IP. Required for the @bypass client_ip matcher below
# to actually match operator IPs (otherwise we only see Cloudflare's edge).
{
    # Email Let's Encrypt for cert renewal notifications (optional)
    # email you@axmcamclub.com

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

axmcamclub.com, www.axmcamclub.com {
    encode gzip zstd

    header {
        X-Content-Type-Options        "nosniff"
        Referrer-Policy               "strict-origin-when-cross-origin"
        X-Frame-Options               "DENY"
        Permissions-Policy            "geolocation=(), microphone=(), camera=()"
        -Server
    }

    # ----- IP ALLOW-LIST (operators) ----------------------------------
    # The enable-maintenance.ps1 script rewrites this list at install
    # time. Add as many client_ip lines as you need, separated by spaces.
    # Use 0.0.0.0/0 to disable allow-listing entirely (everyone sees
    # the maintenance page).
    @bypass {
        client_ip OPERATOR_IPS_PLACEHOLDER
    }

    # Operators on the allow-list get the real site, reverse-proxied
    # exactly like the live Caddyfile.
    handle @bypass {
        reverse_proxy 127.0.0.1:8080 {
            header_up X-Real-IP        {remote_host}
            header_up X-Forwarded-For  {remote_host}
            header_up X-Forwarded-Proto {scheme}
        }
    }

    # Everyone else sees the maintenance page (HTTP 503 — tells search
    # engines to retry later instead of de-indexing the site).
    handle {
        root * C:/Caddy/maintenance
        rewrite * /maintenance.html
        file_server
        header Cache-Control "no-store, no-cache, must-revalidate"
        # 503 = Service Unavailable. Reset to 200 if you'd rather the
        # page load with no error styling in browsers.
        respond 503
    }

    log {
        output file C:\Caddy\logs\axmclub.log {
            roll_size 10MiB
            roll_keep  7
        }
        format console
    }
}
