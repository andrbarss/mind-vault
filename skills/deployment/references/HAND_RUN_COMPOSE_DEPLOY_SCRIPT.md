# A hand-run deploy script for one Compose service: release directories, rollback, a smoke that can fail

Companion reference to [`../SKILL.md`](../SKILL.md). Load it when writing or reviewing a script an operator runs by
hand on the host to deploy a tagged version of a single-container service (`deploy.sh <tag>`), with a health wait, a
smoke check and an automatic return to the previous version. Everything below was measured while building one and
having it reviewed three times; each item is a way the first design was wrong.

## Shape that held

- **Releases are exported directories, the checkout never moves.** `git archive <tag> | tar -x` into
  `releases/<tag>-<UTC stamp>/` (under `pipefail`, a partial directory removed). A script that checks out the tag
  rewrites itself while it runs. A rollback is then "start the previous directory with the previous image": no build,
  no git operation that can fail.
- **One image reference per build** (`<repo>:<tag>-<stamp>`), so a rebuild of the same tag (a base-image patch) does
  not overwrite the image a rollback needs. **One fixed Compose project name** for every release directory, so `up`
  from a new directory replaces the container instead of starting a second one.
- **A release carries a copy of the host-side env file** (no credential in it). A failure caused by an env edit is
  then really undone by the rollback; with one shared env file the "rolled back" release starts with the same bad
  value and still reports success.
- **One hardened base service, extended twice.** Put build, hardening and health check in a base Compose file and
  let the test stack and the production file `extends` it; the security checks then test the lines production runs.
  Measured: `cap_drop`, `security_opt`, `volumes`, `ports` concatenate (an extending file cannot remove hardening);
  a `tmpfs` entry with the same target replaces the base entry; `depends_on` in the base fails; relative paths
  resolve against the base file's directory; `docker compose config` of the test stack should be byte-identical
  before and after the extraction — diff it.
- **Only tags on the default branch** (`git merge-base --is-ancestor`), a tag pattern that cannot start with `-` or
  `.`, and the env file **parsed, never sourced** (known names only, no empty value: an empty assignment reaches the
  container as an empty string and can switch a setting off).

## Traps

1. **`docker compose up` builds silently.** With `build:` present and the image missing, `up` builds it from the
   release directory, without `--pull`, and replaces the running container. Every `up` and `run` outside the one
   build step gets `--no-build` / `--pull never`; so does any `docker run` used to read a version. Before any
   change, `docker image inspect` the image a rollback would need and warn when it is gone (a host-wide
   `docker image prune -a` removes it).
2. **A switch cuts requests in flight.** Docker's default stop grace cut a request waiting on an upstream call. Set
   `stop_grace_period` to cover the **number of sequential upstream calls** one request makes, times the upstream
   timeout, plus a margin — one timeout is not enough when a request makes two calls. Validate it in the script
   against the timeout variable. Prove it with a scenario that holds the switch until the request is in flight (a
   poll for a state file races).
3. **"First deploy" must be read from Docker, not from the state files.** "No previous release → take the failed
   one down" keyed on state files removes a serving container the day the state directory is lost. Refuse when a
   container exists that the state does not describe.
4. **The record of success must not pass through another file system.** Writing the new state to a file under
   `$TMPDIR`, copying it into place and comparing the two compares a truncated file with itself when `/tmp` is
   full: `DEPLOYED`, exit 0, an empty record. Hold the text in the shell, check that it names the release before
   writing, write beside the target, rename (previous first), read back from the target. Print "write these lines
   by hand" from the same shell value, never through a helper that captures into a temp file. No here-string
   either: some bash versions back those with a temp file.
5. **A lost output reader kills the run mid-switch.** `deploy.sh … | tee log` and Ctrl-C, or ssh without a pty
   dropping: the next write gets SIGPIPE and the return to the previous release never runs. `trap '' PIPE` is not
   enough: on bash 3.2 a builtin `printf` that then fails leaves its text in the shell's buffer, and it comes out
   in the **next command substitution** (a timeout read back as `45\ndeploy: returning to …`). Write every line
   from a subshell, send Compose's and the smoke's output to a file from the switch on and print it afterwards
   (a Go program can still die on a broken stdout), keep a run log, and tell the operator to use tmux.
6. **A baseline smoke needs an escape hatch.** Running the current release's smoke before the switch turns an
   environment failure into "nothing changed" instead of a pointless switch and rollback — but when the fix *is*
   a new env value, the baseline blocks the deploy that would fix it. Give it an explicit `--no-baseline`.
7. **Unhealthy-but-running costs the health check's own patience.** `up --wait` reported unhealthy after 150 s
   with the service's timings; a healthy start reports in 1–2 s. Pass `--wait-timeout`.
8. **State writes, lock and pending note.** Check every state write and exit non-zero with the lines to write by
   hand; create the lock atomically with the pid already in it (a hard link to a prepared file), treat an empty or
   unreadable lock and another user's live process (`kill -0` fails with EPERM — use `ps -p`) as held; write a
   pending note before the switch and clear it only when the recorded release is what runs.
9. **The operator's shell leaks into Compose.** Compose prefers a shell variable to the env file's. The script
   unsets its known names; the by-hand recovery command it prints must do the same (`env -u NAME …`).
10. **Bind mounts create missing host paths as root.** A typo in the clients directory becomes "no valid client".
    Long syntax with `bind.create_host_path: false`, plus an existence check.

## Behind a host-side proxy on a rootless daemon

Under rootless Docker (slirp4netns, builtin port driver) the container does not see the caller: every connection
through a published port arrives from one internal address, documented as the bridge gateway of the container's
network. The app's trusted-proxy setting must name that address, and four things follow.

11. **Pin the project network's subnet** (`networks.default.ipam.config.subnet` from a required variable), so the
    gateway is known before the first start and survives `down`/`up`. An address Docker picks is an observation that
    changes whenever the network is made again, while a release's env copy keeps the old one. Keep the example
    outside Docker's default pools: a fixed `/24` inside `172.31.0.0/16` failed with "Pool overlaps" once a later
    automatic network had taken that block (measured). Refuse 10/8 where slirp4netns or the provider network uses it.
12. **A subnet cannot change inside a deploy.** A `compose run` with the new subnet fails with "has active
    endpoints" while the old container serves; with an unchanged container one Compose version recreated the
    network and then failed to start the container, leaving it stopped, and a newer one restarted it. Refuse the
    change in the checks phase (compare with `docker network inspect`), for a rollback too, and document `down` then
    deploy. Tell "the network does not exist" from "inspect failed".
13. **Read the gateway from the container, not from the network.** One engine major leaves a network's IPAM
    gateway empty when only a subnet was given; the next fills it in. A post-start check written on the newer one
    took every release down on the older — the one production ran. `docker inspect -f '{{range
    .NetworkSettings.Networks}}{{.Gateway}} {{end}}' <container>` answers on both. Run the harness on the engine
    version production has; CI was the only place that did.
14. **Compare the trusted-proxy value the way the app reads it.** Compute the expected gateway before the build and
    check it against the setting by CIDR arithmetic, verified against the app's own parser on a table of inputs: a
    prefix `/08` is octal to bash arithmetic (an abort, not a refusal) — use `10#`; three-digit prefixes and
    IPv4-mapped IPv6 forms differ too. Warn in both directions: port on loopback and gateway not trusted (every
    caller is one address; an `https://` smoke cannot pass), and gateway trusted with the port off loopback (any
    caller can then set the forwarded headers).

What a first deploy does **not** show: a smoke to the loopback port passes whatever the peer is, and a log line that
names no address measures nothing. The signals that vary are an `https://` URL through the proxy (it fails on the
scheme when the peer is not trusted) and a pair of requests with a forged `X-Forwarded-Proto`, one through the
published port and one from a throwaway container on the project's network. With the gateway trusted, the trust
boundary is the host's loopback: a local process that posts to the published port is believed. Say so in the
decision record. And check what the host proxy does with `X-Forwarded-Proto` from a caller that skipped the edge:
passed through, it satisfies a "require TLS" rule over plain HTTP.

## A smoke that cannot pass on a broken deployment

When every refusal of the API answers the same bytes (a deliberate property: no oracle for strangers), "the refused
request was refused" proves nothing: a missing `Content-Type`, an empty client registry and a wrong password all
look the same from outside. Assert on the service's **own log line**:

- The request path is usually the only logged field the caller chooses. Send `GET /<random A>`, the real request,
  `GET /<random B>`; the real request's line is the one between the two marker lines. Finding it "by position after
  an offset" fails a good release under concurrent traffic or a log rotation, or lets a foreign line stand in.
- Assert the **exact outcome** in that line, the scheme the URL used (a mismatch means the trusted-proxy setting
  is wrong), and that the random password and a random body marker are absent from the bracket. That the same read
  finds the line is the positive control for "does not find the password".
- Pin the request's `Content-Type`; never follow a redirect (a 301 on plain HTTP breaks a client that POSTs to
  `http://`); `curl -q --noproxy '*'` so `~/.curlrc` and proxy variables cannot change the result.
- A log level above the request lines' level makes a good release fail its smoke: refuse that level in the env
  file check.
- Count what the smoke costs: each run is a failed login from the deploy host's address against the login limit.
- Never send a request with a side effect upstream (a pull that marks records delivered, a price update).

## The harness

Run the real script against a local production-shaped stack: a throwaway git repository built from the working
tree, a good tag and deliberately broken ones, its own project name, image repository and port, generated synthetic
client files. Worth having as scenarios: first deploy; never healthy (returns); smoke fails (returns); rebuild;
rollback; refused before any change (branch name, tag off the default branch, missing env, held lock); the smoke
through a small proxy (real `https`, a false `https`, a 301); a request in flight across a switch; the image to
return to gone (the "state unknown" exit); an unwritable state directory; a reader that leaves at the switch.

- **An assertion that greps the whole output can pass on text an earlier step printed** (the baseline smoke's
  `ok` line satisfied "the return ran the smoke"; Compose's own progress lines satisfied "`ps` is printed"). Assert
  on the part of the output after the step's own heading, and mutate each fix away once to see the check go red.
- On Linux CI the temp directories need explicit modes for the container's uid (`mktemp -d` is 0700); Docker
  Desktop on macOS maps ownership and hides it. Run the harness on both, with the system bash 3.2 on macOS and
  `bash -n` under a `bash:3.2` image in lint (shellcheck has no 3.2 dialect).
- `docker rmi -f` on a running container's image only untags it: record the id and remove it by id in cleanup.
