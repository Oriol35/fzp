# Disk space and number of files per extension, biggest first
find . -path ./.git -prune -o -type f -printf '%s\t%f\n' |
  awk -F'\t' '{ ext = ($2 ~ /\./) ? $2 : "(none)"; sub(/^.*\./, "", ext); n[ext]++; s[ext] += $1 }
    END { for (e in n) printf "%10.1f KB  %5d files  %s\n", s[e]/1024, n[e], e }' | sort -rn
