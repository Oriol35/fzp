# Where an HTTP request spends its time: DNS, connect, TLS, first byte, total
curl -o /dev/null -sS -w 'dns         %{time_namelookup}s\nconnect     %{time_connect}s\ntls         %{time_appconnect}s\nfirst byte  %{time_starttransfer}s\ntotal       %{time_total}s\nstatus      %{http_code}, %{size_download} bytes\n' [URL]
