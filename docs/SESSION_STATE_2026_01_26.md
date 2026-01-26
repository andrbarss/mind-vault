# Session State - 2026-01-26

## Current Status

**Goal**: Extract generic patterns from Teisutis into reusable mind-vault skills

**What's Done**:
✅ mind-vault project created and initialized (~/projects/mind-vault)
✅ Symlinked to both ~/.claude/skills and ~/.config/opencode/skills
✅ GitHub remote set up (infohata/mind-vault)
✅ Scanned Teisutis codebase for AI/rules/config
✅ Filtered scan to generic patterns only (removed Teisutis-specific items)
✅ Created TEISUTIS_SCAN.md documenting 9 generic patterns

**What's Next**:
⏳ Init Teisutis with OpenCode (`cd ~/projects/teisutis && opencode && /init`)
⏳ Discuss implementation approach (skills vs guardrails vs commands)
⏳ Create actual SKILL.md files for each pattern
⏳ Create RULE.md files for guardrails
⏳ Create COMMAND.md files for shortcuts

## 9 Generic Patterns Identified

### Skills (5)
1. `django-async-patterns` - WebSocket + Channels async/sync mixing
2. `django-tenants-patterns` - Multi-tenant context management
3. `error-handling-async` - Error categorization in async code
4. `performance-monitoring` - Observability and monitoring
5. `streaming-response-pattern` - Real-time response handling

### Guardrails (1)
6. `tool-dependency-rules` - Sequential execution, prevent race conditions

### Commands (1+)
7. `dev-shortcuts` - `/rr` (restart + collect static), etc.

### Supporting (1)
8. Database query optimization
9. Django settings patterns

## Key Documents

**Location**: `/home/kestas/projects/mind-vault/docs/TEISUTIS_SCAN.md`

This document has:
- Each pattern explained
- Why it's generic (applies beyond Teisutis)
- Where to use it (format: skill/rule/command)
- Suggested directory structure

## Memory Files

**Teisutis memory**: `~/.claude/memory/projects/teisutis.md`
**Global memory**: `~/.claude/CLAUDE.md` (mentions mind-vault and OpenCode platform)

## Files Changed in This Session

1. `~/.claude/CLAUDE.md` - Updated to reflect OpenCode platform and mind-vault setup
2. `~/.claude/memory/projects/teisutis.md` - Session state tracking
3. `~/projects/mind-vault/README.md` - Project documentation
4. `~/projects/mind-vault/.gitignore` - Security settings
5. `~/projects/mind-vault/docs/TEISUTIS_SCAN.md` - Generic patterns scan (main deliverable)

## GitHub Status

**mind-vault repo**: https://github.com/infohata/mind-vault

Current commits:
1. Initial structure (skills, agents, rules dirs)
2. Path updates for ~/projects/mind-vault
3. TEISUTIS_SCAN.md (detailed patterns)
4. Rewrite to filter generic patterns

All committed and pushed.

## Remaining Questions for Next Session

1. **Implementation format**: For each pattern, confirm:
   - Should it be a SKILL.md? 
   - Should it be a RULE.md (system-level guardrail)?
   - Should it be a COMMAND.md (workflow shortcut)?
   
2. **Priority order**: Which patterns to implement first?

3. **Integration**: How to make patterns discoverable?
   - Via OpenCode skill tool?
   - Via agent rules?
   - Via custom commands?

## Quick Reference

**mind-vault location**: `~/projects/mind-vault/`
**Skills symlink**: `~/.claude/skills` → `~/projects/mind-vault/skills`
**OpenCode symlink**: `~/.config/opencode/skills` → `~/projects/mind-vault/skills`
**Teisutis location**: `~/projects/teisutis/`
**Scan document**: `~/projects/mind-vault/docs/TEISUTIS_SCAN.md`

## Next Session Command

```bash
cd ~/projects/teisutis
opencode
# Then discuss patterns with full project context
```
