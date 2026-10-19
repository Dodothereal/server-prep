---
name: monitoring
description: Connect a server's Telegraf to InfluxDB v2 and show it in the shared Grafana dashboard (bucket/host variables, portable Flux queries). Use for Telegraf, InfluxDB, Grafana or "metrics not showing" questions.
---

# Telegraf → InfluxDB → Grafana

server-prep installs Telegraf **stopped**. This skill connects it.

## 1. Output config (token kept out of the main config)
The user needs:
- an InfluxDB bucket for this server (convention: **one bucket per server, named after it**);
- a write token for that bucket.

```bash
sudo cp extras/telegraf/influxdb.conf.example /etc/telegraf/telegraf.d/influxdb.conf
sudo nano /etc/telegraf/telegraf.d/influxdb.conf          # set urls, organization, bucket
echo 'INFLUX_TOKEN=<paste-token>' | sudo tee /etc/default/telegraf >/dev/null
sudo chown root:telegraf /etc/default/telegraf /etc/telegraf/telegraf.d/influxdb.conf
sudo chmod 640 /etc/default/telegraf /etc/telegraf/telegraf.d/influxdb.conf
```

Optional:
- Docker metrics: `sudo usermod -aG docker telegraf`. This grants root-equivalent access.
- To show the bucket name instead of the OS host name: `hostname = "<name>"` under `[agent]`.

## 2. Test: send one real batch
```bash
sudo -u telegraf env $(sudo cat /etc/default/telegraf) telegraf --config /etc/telegraf/telegraf.conf \
  --config-directory /etc/telegraf/telegraf.d --once --debug 2>&1 | tail -20
```

How to read the output:
- **OK:** `Wrote batch of N metrics`.
- **401:** bad token.
- **404:** wrong bucket or org.
- **refused / timeout:** wrong URL, or the server can't reach InfluxDB over Tailscale.
- **Noise:** `permission denied` on docker, gvfs or netns mounts, `utmp` missing, docker `parsing size`.

`--test` never sends data, so use `--once`.

## 3. Start
```bash
sudo systemctl enable --now telegraf && journalctl -u telegraf -f    # no E! lines
```

## 4. Grafana dashboard (shared by all servers)
**Variables**, in this order:
1. `bucket`: query `buckets()`.
2. `host`:
   - query:
     ```flux
     import "influxdata/influxdb/schema"
     schema.tagValues(bucket: "${bucket}", tag: "host", start: -1h)
     ```
   - single value, no "All", optionally hidden. It then follows the selected bucket automatically.

**Query rules** that make panels work on every OS:
- Always filter with `r.host == "${host}"`. Never assume host = bucket.
- **Disk:** filter on `r.path == "/"`, not on the device. The device is `vda1` on the VPS but `nvme0n1pX` on the laptop.
- **Network:** filter with `r.interface !~ /^(lo|docker|veth|br-|tailscale)/` rather than naming `eth0` / `enp*`.
- **CPU:** `r.cpu == "cpu-total"`, and use `100 - usage_idle`.

Example (disk usage of `/`):
```flux
from(bucket: "${bucket}")
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r._measurement == "disk" and r._field == "used_percent")
  |> filter(fn: (r) => r.host == "${host}" and r.path == "/")
  |> aggregateWindow(every: v.windowPeriod, fn: last, createEmpty: false)
```

To change every panel at once, edit the dashboard JSON Model (Settings → JSON Model) and use find/replace.
