# The 20 largest folders here, without crossing into other disks (like /mnt/c on WSL)
du -xh --max-depth=1 . 2>/dev/null | sort -rh | head -20
