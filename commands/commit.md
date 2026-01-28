---
description: Create semantic commit with conventional commit format
agent: general
---

Execute the commit command to create a semantic commit with conventional commit format.

Steps to follow:
1. Check git status to see staged and unstaged changes:
   - Run git status
   - Run git diff --cached to see staged changes
   - Run git diff to see unstaged changes

2. Analyze the changes to understand what was modified:
   - Look at file names and paths to determine the scope (e.g., feat, fix, docs, refactor)
   - Examine the diff content to understand the nature of changes

3. Generate a semantic commit message following conventional commit format:
   - Format: type(scope): description (≤72 chars)
   - Types: feat, fix, docs, style, refactor, test, chore
   - Scope: optional, e.g., (auth), (api)
   - Description: imperative mood, present tense
   - Add body if needed for complex changes

4. If there are unstaged changes, ask user if they want to stage them first

5. Commit the changes using the generated message:
   - Run git commit -m "generated message"

6. Provide confirmation of the commit

Requirements:
- Must be on a feature branch (not main)
- Changes should be staged before committing