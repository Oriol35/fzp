# Processes using the most memory, with how long they've been running
ps -eo pid,user,%cpu,%mem,rss,etime,comm --sort=-rss | head -15
