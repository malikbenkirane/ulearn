# TIL: Running Local DNS on macOS with Dnsmasq

**Use Dnsmasq + macOS resolver directory to route custom domains (like `.test`) to localhost — no `/etc/hosts` edits needed.**

1. `brew install dnsmasq`
2. `echo "address=/.test/127.0.0.1" >> $(brew --prefix)/etc/dnsmasq.conf`
3. `sudo brew services start dnsmasq` (port 53 requires sudo)
4. Create `/etc/resolver/test` with `nameserver 127.0.0.1`

**Key insight:** macOS has a scoped resolver system via `/etc/resolver/<domain>`. This routes *only* `.test` queries to Dnsmasq, leaving all other DNS untouched. Don't edit `/etc/resolv.conf` — macOS regenerates it and you'd break your internet.

**Gotcha:** `nslookup`, `dig`, and `host` bypass the macOS resolver entirely and go straight to your network DNS (e.g. 8.8.8.8). They'll return `NXDOMAIN` even when everything works. Test with `ping` or `curl` instead, which use the system resolver. Or force nslookup: `nslookup litellm.test 127.0.0.1`.