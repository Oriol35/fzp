# Delete the local git branches already merged into main (look at the list first, then delete)
git fetch --prune
# 1. See what would go:
git branch --merged origin/main | grep -vE '^\*|^[[:space:]]*(main|master|develop)$'
# 2. Delete them:
git branch --merged origin/main | grep -vE '^\*|^[[:space:]]*(main|master|develop)$' | xargs -r git branch -d
