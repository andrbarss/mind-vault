# `php:*-apache` as non-root on a read-only file system

Load when hardening a container on the official `php:*-apache` image, or reviewing one. All of it was measured on PHP 8.5, Apache 2.4 prefork, Debian 13, Docker 29.

## The shape that works

```yaml
read_only: true
cap_drop: [ALL]
security_opt: ["no-new-privileges:true"]
sysctls:
  net.ipv4.ip_unprivileged_port_start: "0"   # keeps port 80: no URL in harnesses or proxies changes
tmpfs:
  - /tmp:mode=1777,size=128m                 # a request body over 16 KiB spills here, up to twice
  - /var/run/apache2:uid=33,gid=33,size=1m
  - /var/lock/apache2:uid=33,gid=33,size=1m
```

Plus `USER www-data` in the image's runtime stage, after the `COPY`s, so the app's files stay root's. The image's Apache directories are already `www-data`, and `ErrorLog /proc/self/fd/2` still works. Without this, spilled bodies reach the writable layer, passwords included.

- **A tmpfs needs `uid=33`** when the entrypoint writes to it as www-data. A root-owned one makes the start fail.
- **An entrypoint that "drops to www-data" after a root step** often protects little: if www-data must read the compiled secrets anyway, the root step guards nothing. Say what is lost: www-data then owns a file PHP `require`s.
- **The test stage inherits `USER`:** PHPUnit's result cache warns under a read-only `/app`. Use `--cache-directory /tmp/…` (`--do-not-cache-result` is deprecated in PHPUnit 13).
- **Client or secret files on the host** must now be readable by uid 33, and a log directory writable by it. Write that into the deploy notes in the same PR.
- `a2dismod -f status autoindex negotiation alias` all start cleanly; `/server-status` and `/icons/` then reach the app's 404. `ServerTokens Prod` and `ServerSignature Off` go in `conf-available/security.conf` by `sed`: a new conf file sorting before `security.conf` is overridden by it.
- **Size the workers:** `MaxRequestWorkers` defaults to 150, far past what most hosts can hold at peak per-worker memory. libxml's memory is outside `memory_limit`.

## Make the unsafe start refuse

`docker run` without the Compose settings starts happily, with secrets on the writable layer; as root it can answer the health check while refusing every login. Have the entrypoint refuse:

```sh
[ "$(id -u)" != 0 ] || { echo "running as root; refusing to start" >&2; exit 1; }
for dir in "$(dirname "$COMPILED_SECRETS")" /tmp; do
    [ "$(stat -f -c %T "$dir")" = tmpfs ] || { echo "$dir is not a tmpfs; refusing to start" >&2; exit 1; }
done
```

## Checks that prove it

- ❌ `touch /app/x` fails: it also fails for uid 33 on a **writable** root, because root owns `/app`. Same for `touch /x`.
- ✅ `/` is `ro` in `/proc/mounts`, **and** a write fails in a directory www-data owns (`/var/log/apache2`). That write succeeds without `read_only`.
- ✅ From `/proc/1/status`: `Uid` 33, `CapEff` all zeros, `NoNewPrivs` 1.
- ✅ Run the same script in the container *without* the settings and read it fail. A check never seen failing is not yet a check.
