# mind-vault

AI agent configuration, skills, and rules for Claude Code and OpenCode.

## Structure

- **`skills/`** - Reusable agent skills (SKILL.md files)
  - Discoverable by OpenCode and Claude Code
  - Loaded on-demand, zero context overhead
  - Project-specific and global patterns

- **`agents/`** - Custom agent definitions
  - Agent configuration and specialization
  - Project-specific agent rules

- **`rules/`** - Shared behavioral rules
  - Coding conventions
  - Architecture patterns
  - Best practices

## Symlinks

From `~/.claude/` and `~/.config/opencode/`:
```bash
ln -s ~/mind-vault/skills ~/.claude/skills
ln -s ~/mind-vault/skills ~/.config/opencode/skills
```

Both Claude Code and OpenCode will discover skills from this vault.

## Usage

In OpenCode or Claude Code, reference skills by name:
- Ask: "Load the teisutis-django-orm skill"
- Or implicitly: OpenCode will find relevant skills

## Version Control

Commit all non-sensitive configuration to git.

⚠️ **Never commit**: API keys, credentials, passwords, tokens
✅ **Do commit**: Skills, agent rules, coding conventions, patterns
