# Backwards Compatibility Tracking

**Purpose**: Document skills/rules that may NOT be fully compatible with current Teisutis architecture/setup  
**Date**: 2026-01-26  
**Status**: Active (Insurance Policy)  
**Applies To**: mind-vault - Teisutis project integration

---

## Overview

This document tracks which skills and rules may have compatibility gaps with Teisutis's current setup. Use this as an "insurance policy" to:
- Identify potential integration issues before they become bugs
- Document workarounds or adaptations needed
- Track when Teisutis architecture changes require skill updates
- Prevent blindly copying patterns that don't work in Teisutis context

---

## Tracking Table

| Skill/Rule | Component | Status | Issue | Workaround/Notes | Last Checked |
|-----------|-----------|--------|-------|------------------|--------------|
| SKILL_django-architecture | Flat app structure | ✅ COMPATIBLE | Teisutis uses flat apps in `web/` dir (auth, core, api, etc.) | Identical structure - can directly apply | 2026-01-26 |
| SKILL_django-architecture | web/ subdirectory | ✅ COMPATIBLE | Teisutis separates infrastructure (docker, nginx, docs) from Django code | Skills now document this pattern explicitly | 2026-01-26 |
| SKILL_django-architecture | BaseModel soft deletes | ✅ COMPATIBLE | Teisutis uses this pattern extensively | Can directly apply to new models | 2026-01-26 |
| SKILL_django-architecture | DRF ViewSets | ✅ COMPATIBLE | Teisutis DRF patterns match skill | Can directly apply | 2026-01-26 |
| SKILL_django-architecture | ASGI/Daphne | ✅ COMPATIBLE | Teisutis uses Daphne setup | Can directly apply | 2026-01-26 |
| SKILL_django-architecture | Modular views/tests | ✅ COMPATIBLE | Teisutis auth app uses this pattern | Can directly apply | 2026-01-26 |
| SKILL_django-multi-tenant | TenantModel inheritance | ✅ COMPATIBLE | Teisutis uses django-tenants | Foundation for this skill | TBD |
| SKILL_django-multi-tenant | Middleware ordering | ⚠️ VERIFY | Teisutis has specific middleware requirements | Verify against current settings.py before deploying | TBD |
| SKILL_django-celery | Signal-based task triggering | ✅ COMPATIBLE | Teisutis uses this approach | Can directly apply | TBD |
| SKILL_django-celery | Tenant context in tasks | ✅ COMPATIBLE | Teisutis explicitly passes tenant_id | Can directly apply | TBD |
| SKILL_django-async-websocket | @database_sync_to_async | ✅ COMPATIBLE | Teisutis uses extensively | Can directly apply | TBD |
| SKILL_django-async-websocket | Tenant context in async | ✅ COMPATIBLE | Teisutis uses tenant_context(tenant) in consumers | Can directly apply | TBD |
| RULE_commit-approval | Every commit needs approval | ✅ COMPATIBLE | Principle is universal | Apply to all work | 2026-01-26 |
| RULE_git-workflow | Branch strategy | ✅ COMPATIBLE | Principle is universal | Apply to all work | 2026-01-26 |

---

## Known Integration Gaps

*(None currently identified - skills aligned with Teisutis architecture)*

### Past Issues (Resolved)

**Issue**: App structure mismatch (RESOLVED)
- **Initial Thought**: Teisutis uses nested `web/teisutis_*` apps
- **Reality**: Teisutis uses flat apps in `web/` (auth, core, api, not prefixed)
- **Resolution**: Skills updated to document `web/` subdirectory pattern correctly
- **Status**: ✅ RESOLVED - Skills now match Teisutis exactly

---

## Verification Checklist (Before Deploying Skills to Teisutis)

- [ ] Multi-tenant skill tested against Teisutis tenant resolution middleware
- [ ] Celery skill tested against actual Teisutis signal handlers and tasks
- [ ] Async skill tested against actual Teisutis consumers
- [ ] Middleware ordering verified in Teisutis settings.py
- [ ] Permission layer testing verified against Teisutis RBAC
- [ ] Database isolation verified with multi-tenant queries
- [ ] Soft delete queries verified (is_deleted=False filtering)

---

## Update Frequency

**Review when**:
- New skill is created
- Teisutis architecture changes significantly
- A skill is used in Teisutis project and issues are found
- New versions of Django, DRF, django-tenants, Celery released

**Last Audit**: 2026-01-26 (Initial setup)  
**Next Audit**: After Phase 2-4 skill creation complete

---

## Issue Resolution Process

1. **Find Issue**: Developer discovers skill doesn't work with Teisutis setup
2. **Document Here**: Add row to tracking table with status `⚠️ ISSUE`
3. **Investigate**: Determine if issue is:
   - Skill error (fix skill)
   - Teisutis-specific (add workaround)
   - Version mismatch (document version requirement)
4. **Resolve**: Either fix skill or document workaround
5. **Update Status**: Change status back to ✅ or ⚠️ WORKAROUND

---

## Related Documents

- [`TEISUTIS_ARCHITECTURE_ANALYSIS.md`](TEISUTIS_ARCHITECTURE_ANALYSIS.md) - Technical analysis used to create skills
- [`DJANGO_ARCHITECTURE_PLAN.md`](DJANGO_ARCHITECTURE_PLAN.md) - Skill development roadmap
- Skills: 
  - `skills/SKILL_django-architecture.md`
  - `skills/SKILL_django-multi-tenant.md` (in progress)
  - `skills/SKILL_django-celery.md` (in progress)
  - `skills/SKILL_django-async-websocket.md` (in progress)

---

**Last Updated**: 2026-01-26  
**Maintained By**: mind-vault team  
**Purpose**: Insurance policy for skill/Teisutis compatibility
