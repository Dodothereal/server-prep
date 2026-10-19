# server-preconfig: first setup of a new server

Run `server-preconfig.sh` **once, right after installing Debian/Ubuntu, before `server-prep.sh`**. It makes the server reachable and makes sure it **comes back on its own** after a reboot or a power cut: network, SSH and Tailscale.

| What it does | Why |
|---|---|
| Installs `openssh-server sudo curl jq iputils-ping` (only the missing ones), and starts and enables SSH | A Debian install without the "SSH server" option refuses connections |
| Puts the admin user in the `sudo` group, and can add its SSH keys from `github.com/<login>.keys` | If a root password is set during install, Debian creates the user **without** sudo |
| Sets the hostname, plus `/etc/hosts` and the Tailscale name | Your panel, monitoring (host/bucket) and Tailscale all use it. `/etc/hosts` stops the "unable to resolve host" warning |
| Saves the network in `/etc/network/interfaces.d/<iface>` (fixed IP or DHCP) and disables older definitions | An IP set by hand is **lost at reboot**, which means no internet, no Tailscale and no SSH |
| Masks sleep, suspend and hibernate, and makes logind ignore idle | A server must never go to sleep |
| Installs Tailscale and logs it in (login URL, or `TS_AUTHKEY`) | The panel and the admins reach the server through the tailnet, whatever the LAN IP |
| **Checks** that everything will come back after a reboot | You find problems before the reboot, not after |

**VPS or dedicated server:**
- **On a VPS**, the provider manages the network (netplan / cloud-init). The script doesn't touch it: press Enter (`keep`) at the network question. You mostly get SSH + sudo, the hostname and Tailscale.
- **On a dedicated or on-premise server**, saving the network and disabling sleep are what make it come back after a reboot or a power cut.

It only changes what is needed and can be re-run. Changed files are backed up to `/var/lib/server-prep/backups/preconfig-<date>/`.

## 1. Get the script onto the server

You need SSH on the LAN, or the console.

- **SSH already works on the LAN** (password login):
  ```bash
  # from your workstation, in the repo folder
  scp -r . <user>@<lan-ip>:~/server-prep
  ```
- **SSH refused**: at the console, as root, run `apt install -y openssh-server`, then use `scp` as above.
- **Internet works on the server**: `git clone https://github.com/exceev-consulting/server-prep.git`

## 2. Run it

```bash
cd ~/server-prep
sudo ./server-preconfig.sh            # no sudo yet? su - -c "$HOME/server-prep/server-preconfig.sh"
```

**The questions** (Enter = default):

| Question | Answer |
|---|---|
| Admin user | your user (default: the one running sudo) |
| GitHub login | e.g. `octocat` to add your workstation's key (it must be on GitHub), or Enter to skip and use `ssh-copy-id` |
| Hostname | e.g. `web-01` (a-z, 0-9, hyphens) |
| Network to save | `current` = keep the current IP as a fixed IP · `192.168.1.50/24` · `dhcp` · `keep`. The default is `current` when the IP isn't saved, otherwise `keep` |
| Gateway | default: the current one |
| Tailscale | `yes`. Open the printed URL on your workstation and approve the machine |

Without questions:
```bash
sudo ./server-preconfig.sh --hostname web-01 --static-ip current --github-keys octocat --yes
```
Other options: `--dry-run` previews the changes, `--check` only runs the checks, and `--help` lists everything.

## 3. Read the result

| Line | Meaning |
|---|---|
| `OK eno1 saved as static (192.168.1.50/24)` | the network will come back after a reboot |
| `FAIL eno1 is not saved` | re-run with `--static-ip current` (or `dhcp`) |
| `OK networking / ssh / tailscaled enabled at boot` | the services start by themselves |
| `OK sleep/suspend/hibernate masked` | it never goes to sleep |
| `WARN Tailscale key expires <date>` | Tailscale admin console → Machines → the server → `…` → **Disable key expiry**, otherwise access is cut on that date |
| `WARN <user> has no SSH key` | from your workstation: `ssh-copy-id <user>@<tailscale-ip>` (needed: server-prep disables password login) |

**Two things the script can't do:**
1. **BIOS:** set *Restore on AC Power Loss* to **Power On**, or the server stays off after a power cut.
2. **Router:** a fixed IP must be **outside the DHCP range**, or reserved for this server.

## 4. Reboot test, then server-prep

```bash
sudo reboot
# ~2 minutes later, from your workstation:
ssh <user>@<tailscale-ip> 'hostname; ip -br a show eno1; ping -c2 debian.org'
```
If that works, the server comes back on its own. Continue with `server-prep.sh` (README.md, or `/new-server` in Claude Code).

## Troubleshooting (seen on real servers)

| Symptom | Cause | Fix |
|---|---|---|
| `Connection refused` on SSH | `openssh-server` is not installed | at the console: `apt install -y openssh-server` |
| `Permission denied` as root | Debian refuses root password login over SSH | log in with your user |
| `Could not open lock file … are you root?` | `sudo a && b`: only `a` runs as root | `sudo a && sudo b` |
| `Authentication failed` at `[sudo: authenticate]` | a token or the next command was typed or pasted at **sudo's** prompt | type the server password, and run commands one at a time |
| `sudo: unable to resolve host <name>` | hostname changed before `/etc/hosts` | harmless. The script updates `/etc/hosts` first |
| No internet or SSH after a power cut | IP set by hand, never saved | `sudo ./server-preconfig.sh --static-ip current` |
| `Some peers are advertising routes but --accept-routes is false` | another device shares a subnet | ignore. Don't enable `--accept-routes` on a LAN server |
| Machine not visible in Tailscale | logged in with another account, or waiting for approval | `tailscale switch --list`, or approve it in Machines |
| `/etc/resolv.conf` says "generated by tailscale" | MagicDNS (100.100.100.100) | normal. The upstream DNS is in `/etc/resolv.pre-tailscale-backup.conf` |
