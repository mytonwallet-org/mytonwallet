# Why this directory is committed

husky writes these files on `npm install`, and git runs hooks from here through
`core.hooksPath`. That setting is shared by every worktree of a clone, so a worktree
that never ran `npm install` would have no hooks and its commits would skip them
silently. Committing the files makes the hooks run in every worktree.

Do not delete them or add `.husky/_` to `.gitignore`. A husky upgrade rewrites
them on `npm install`; commit the changes together with the upgrade.

The `.gitignore` in this directory is husky's own and ignores every file here, so
a hook file that a new husky version adds does not show in `git status`. After an
upgrade, run `git status --ignored .husky/_` and add each file it lists with
`git add -f`, except `.gitignore` and the deprecated `husky.sh`.
