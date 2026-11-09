# Local git branches sorted by last commit, with author and subject
git for-each-ref --sort=-committerdate refs/heads --format='%(committerdate:relative)%09%(refname:short)%09%(authorname)%09%(contents:subject)' | column -t -s $'\t'
