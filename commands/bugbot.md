---
description: Automated code review and PR creation with AI-generated messages
agent: general
---

Execute the bugbot command to perform automated code review and PR creation with AI-generated messages.

Steps to follow:
1. Check current git status and branch:
   - Run git status to see uncommitted changes
   - Run git branch --show-current to get current branch name
   - Ensure it's a feature branch (not main)

2. If there are uncommitted changes:
   - Analyze the changes using git diff --cached and git diff
   - Generate a semantic commit message based on the changes (follow conventional commits format)
   - Commit the changes with the generated message

3. Push to remote branch if not already pushed:
   - Run git push -u origin <branch-name>

4. Generate PR details:
   - Analyze all commits in the branch (git log main..HEAD)
   - Generate a comprehensive PR title and description
   - Title should be clear and descriptive
   - Description should include what changed, why, and any relevant context

5. Create or update the PR:
   - If PR doesn't exist, create it with gh pr create --title "generated title" --body "generated description" --draft
   - If PR exists, update it with gh pr edit --title "generated title" --body "generated description"

6. Invoke bugbot for automated code review:
   - Set environment variables: COMMIT_MSG, PR_TITLE, PR_BODY with the generated messages
   - Run ./tools/bugbot.sh

7. Provide status updates throughout the process

Requirements:
- tools/bugbot.sh script must exist
- gh CLI configured
- Current branch should be a feature branch

Handle errors gracefully and inform the user if any step fails.