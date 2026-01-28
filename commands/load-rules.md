---
description: Reload mind-vault rules after context compaction
agent: general
---

Execute the load-rules command to reload mind-vault rules after context compaction.

Steps to follow:
1. List all RULE_*.md files in the rules/ directory:
   - Use glob tool to find rules/RULE_*.md

2. Read the content of each rule file:
   - Use read tool to get full content of each file

3. Extract key information from each rule:
   - Rule name and principle
   - Key examples and why it matters
   - Any critical limitations

4. Display a summary of all loaded rules:
   - List rule names
   - Show brief description of each
   - Confirm they are active for enforcement

5. Verify no rules are missing or corrupted

6. Provide confirmation that rules have been loaded and are ready for use