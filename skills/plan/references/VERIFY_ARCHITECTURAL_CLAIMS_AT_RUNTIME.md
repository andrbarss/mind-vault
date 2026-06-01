# VERIFY_ARCHITECTURAL_CLAIMS_AT_RUNTIME

Sibling guardrail to [`PROD_DATA_SNIFF_BEFORE_DESIGN_LOCK.md`](PROD_DATA_SNIFF_BEFORE_DESIGN_LOCK.md), same *verify-before-lock* family. That one: a design hinging on a data-shape assumption verified only in dev needs a prod-data sniff before commit. This one: **a claim about a subsystem's *runtime shape* — global vs per-tenant config, request lifecycle, when/where code executes — cannot be confirmed by reading the code at one point.** Source-verification proves the *line*; it does not prove the *lifecycle*.

## The trap

When you (or a fan-out of read-only agents) document or plan around an **unfamiliar subsystem**, the natural verification is: find the line, confirm it says what the doc claims, cite `file:line`. That is necessary but **insufficient for architectural claims**, because the meaning of a line often depends on context that isn't visible at that line:

- A registry/global set like `Registry::set('x', env('X'))` *looks* process-global — but if it runs per-request after a per-tenant env file is loaded, it's actually **per-tenant**. The line is identical either way; only the load order / request lifecycle distinguishes them.
- A "default" constant *looks* like the value — until you learn it's only reached on an unmatched-tenant fallback path.
- A "singleton" *looks* shared — until you learn the process model re-instantiates per request (PHP-FPM, serverless, per-worker).

## Why both agents AND review bots miss it

This blind spot survives the usual safety nets because they all reason from the **same local read**:

- **Fan-out reading agents** map each file in isolation; none owns the request-lifecycle / multi-tenancy context that ties them together. They confidently report the line's apparent meaning.
- **Review bots** (Copilot, Bugbot, etc.) check the diff against itself and the immediate surrounding code — they verify *internal consistency and line-level fidelity*, not whether the architectural framing matches how the system actually runs. They will pass a confidently-wrong "this is global" claim through many rounds while nitpicking type-name fidelity around it.
- **Your own source-verification pass** confirms `file:line` says what you wrote — which feels like rigor but only re-confirms the shallow read.

The result: a load-bearing architectural claim can be **inverted** (e.g. "global, one vendor per deployment" when it's actually "per-tenant, every org picks its own") and clear fan-out + N review rounds + a source-verification pass — caught only by a human who holds the domain/runtime model.

## The rule

When a reference doc or plan makes a **load-bearing architectural claim**, do NOT treat source-verification as sufficient. Either trace the runtime, or flag the claim for human confirmation before locking it. Claims in this class:

- **Scope/granularity of config or state** — global vs per-tenant vs per-request vs per-user. ("X is set once per deployment" / "each org configures its own X.")
- **Request / execution lifecycle** — when code runs, in what order, how many times, in which process. ("This loads once at boot" / "per request").
- **Multi-tenancy model** — single-tenant vs one-instance-many-tenants; how a tenant is resolved (host? header? path? token?).
- **Process / concurrency model** — shared vs per-worker vs per-request isolation (FPM, serverless, threads).
- **Fallback / default reachability** — when the documented default actually fires.

## How to discharge it (cheapest first)

1. **Trace the lifecycle, not just the line.** For a config/registry claim, find where the value's *source* is loaded relative to where it's *set/read*. (E.g. "is the env file loaded per-request before this `set()`? then it's per-request/per-tenant, not global.") One extra grep for the loader + its call site usually settles it.
2. **Look for the tenant-resolution seam.** Multi-tenant apps resolve the tenant somewhere early (host → env, subdomain → DB, header → context). If you can't name it, you don't yet know the granularity — don't assert it.
3. **Ask the human / surface it explicitly.** If 1–2 don't fully settle it, write the claim as an Open Question in the plan, or flag it in the reference's hand-back: *"I've documented X as <global/per-tenant> based on `file:line`; please confirm this matches the runtime model before this is trusted."* One sentence to the maintainer beats shipping an inverted architecture into a reference future readers will trust.

## Anchor case (2026-06)

Documenting an unfamiliar door-lock subsystem in a multi-tenant legacy PHP (Zend Framework 1) app. The guide asserted **"vendor selection is GLOBAL per deployment — one instance = one vendor"**, citing the exact line where a registry key is set from an env var (`Registry::set('locks_factory_class', env('LOCKS_FACTORY_CLASS'))`). That line was real and correctly cited. But the bootstrap loads a **per-tenant env file** (keyed off the request `Host`'s first label) *and then* requires the config file — so the registry is set **per request, from each org's own env**. The true architecture was the opposite: **per-org multi-tenant** — every organisation on the one instance picks its own vendor. The inverted claim cleared a 5-agent fan-out map, a self source-verification pass, and **3 rounds of review-bot review** (which fixed type-name fidelity and an undefined snippet var around the claim while never questioning it). The maintainer caught it in one read. The fix added the host→env→config load-order trace to the doc and reframed per-org selection as the key feature.

**Last Updated**: 2026-06-01
