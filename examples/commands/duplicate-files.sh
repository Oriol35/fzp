# Files with identical content, grouped
find . -path ./.git -prune -o -type f -print0 | xargs -0 sha256sum | sort | uniq -w64 --all-repeated=separate
