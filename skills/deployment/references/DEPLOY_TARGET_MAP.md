# Deploy target map: the hosts that serve the change, and what each one really runs

Load before deploying a service that is in the middle of a host migration, or whose
"deploy" runbook names a single host while the estate has more than one. Two traps, both
silent: a deploy that updates a host the change does not run on, and a redeploy that ships
more than the PR being released.

## Trap 1 — the runbook's host is not the host that serves the tenant

**Shape.** A multi-tenant service runs on host A. A migration moves some tenants (often the
test tenants first, "to try the move") to host B. Host A keeps TLS and proxies their names to
B, so DNS, URLs and the cron launcher look unchanged. The deploy guide still says "deploy =
redeploy on A". B was filled once by copying A's image and files and has **no redeploy mode**.

**What goes wrong.** You release, redeploy A, verify A — every check is green. The live check
then runs on a moved test tenant, which is still on B's old image. It can pass (testing nothing)
or fail (blamed on the release). Environment files are copies on B too: an edit made on A does
not reach B.

**Before every deploy:**

1. List the tenants the change is for (the live-check tenant included), and find the host that
   **runs their code**, not the host their name resolves to. Read the infrastructure notes and
   the changelog of the ops repo since the runbook was last edited: migrations announce
   themselves there, not in the runbook.
2. For each host: read the commit or image it runs now. That is the rollback target, and it also
   shows whether someone already updated it out of band. A host the notes describe as "copied
   on day X" may have been updated since, with no record.
3. For a host with no redeploy mode, write the smallest update before you start:
   - move only the new image between hosts (save → copy host to host → load); don't re-run the
     full copy, which overwrites data that exists only on the target;
   - check which image the host's own tooling will pick ("newest tag wins" is common);
   - re-derive every bind-mounted patched copy of an image file from the **new** image;
   - recreate the container;
   - verify.
4. Watch for idempotence guards that skip work: "already applied: the patched copy matches"
   returns **without recreating** the container, so the old image keeps running. Set the patched
   file aside first, so the apply step rebuilds it and recreates the container.
5. Check each moved tenant's environment file **on its own host** for the flags the release
   needs.
6. Then fix the runbook: name every host, say how each is updated, and record the out-of-band
   update you found.

**Jobs.** A scheduler on host A that calls tenants by public URL runs the job on whichever host
serves the tenant. A scheduler that runs CLI jobs from a local tree runs them on A, on A's
interpreter, whatever image is deployed. Check which kind your job is before saying where it
runs.

## Trap 2 — the release branch is ahead of what is deployed

**Shape.** Release = merge main into a release branch, then redeploy the merge commit. Someone
merged release N into the release branch and never redeployed. You merge release N+1 and
redeploy: the redeploy ships N and N+1.

**Before the redeploy:** read the live commit (step 2 above) and list
`live..release-branch --first-parent`. If it holds more than your release, say so before the
deploy, and ask whoever owns the earlier release whether it is waiting for a measurement or a
window. Two redeploys must not overlap. Report the full delta and the rollback target in the
deploy record.

## Related

- [`BARE_METAL_ATOMIC_RELEASES.md`](BARE_METAL_ATOMIC_RELEASES.md) — release mechanics on one host.
- [`SCREEN_SESSIONS.md`](SCREEN_SESSIONS.md) — running the redeploy remotely.
- [`READING_PRODUCTION_LOGS_WITHOUT_LEAKING.md`](READING_PRODUCTION_LOGS_WITHOUT_LEAKING.md) — the post-deploy log checks.
