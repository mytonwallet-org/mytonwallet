# AIR Android Task

You are helping fix an AIR Android issue for the mytonwallet-dev repo.

## Input: $ARGUMENTS

## Steps

### 1. Fetch the issue
- If the input is a number, fetch the issue from GitHub: `gh issue view <number> --repo mytonwallet-org/mytonwallet-dev`
- If the input is a description, use it directly as the issue context.
- Summarize the issue briefly for the user.

### 2. Understand the codebase context
- Read relevant code to understand the problem. Focus on `mobile/android/` and `src/` as needed.
- Identify the root cause and plan the fix.
- Present your analysis and proposed fix to the user. Wait for confirmation before proceeding.

### 3. Create a branch
- Fetch latest: `git fetch origin master`
- Determine branch name:
  - Bug fix: `air/android/fix/<short-description>`
  - Feature/improvement: `air/android/<short-description>`
- Create and checkout: `git checkout -b <branch> origin/master`

### 4. Implement the fix
- Make the minimal, focused changes needed.
- Follow existing code patterns and conventions.
- Do NOT add unnecessary comments, docs, or refactors.

### 5. Present for review
After implementing, present to the user:

**Suggested commit message:**
```
<type>: <concise description>

<body if needed>
```

**Suggested PR title:** `[Android] <Component/Feature>: <concise description>` (under 70 chars)

**Suggested PR description:**
```
## Summary
- <bullet points>

## Test plan
- [ ] <testing steps>
```

### 6. Wait for user approval
- Do NOT commit, push, or create PR until the user explicitly approves.
- If the user requests changes, apply them and re-present.
- Once approved, commit, push with `-u`, and create the PR using `gh pr create`.
- Add the "AIR Android" label to the PR: `gh pr edit <number> --add-label "AIR Android"`
