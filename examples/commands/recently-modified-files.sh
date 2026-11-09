# Files changed in the last 24 hours, newest first, skipping .git
find . -path ./.git -prune -o -type f -mmin -1440 -printf '%TY-%Tm-%Td %TH:%TM  %p\n' | sort -r
