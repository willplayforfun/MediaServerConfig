#!/usr/bin/env bash
# Read-only security snapshot: listeners, container privileges, firewall, SSH, open admin UIs. No secrets printed.
# Run as root and paste the output back: sudo bash host/security-audit.sh
set -u

section() { printf '\n===== %s =====\n' "$1"; }

command -v curl >/dev/null || { echo "curl is missing: apt install -y curl, then re-run"; exit 1; }

section "Host"
grep PRETTY_NAME /etc/os-release
uname -r
systemctl is-active unattended-upgrades 2>&1 | sed 's/^/unattended-upgrades: /'
docker version --format 'docker {{.Server.Version}}'
cat /etc/docker/daemon.json 2>/dev/null || echo "no /etc/docker/daemon.json"

section "Listening sockets"
ss -tulnp

section "Published container ports"
docker ps --format 'table {{.Names}}\t{{.Ports}}'
docker ps -a --format 'table {{.Names}}\t{{.Status}}'

section "Container privileges"
docker ps -aq | xargs docker inspect --format \
  '{{.Name}} user={{.Config.User}} priv={{.HostConfig.Privileged}} net={{.HostConfig.NetworkMode}} capadd={{.HostConfig.CapAdd}} capdrop={{.HostConfig.CapDrop}} secopt={{.HostConfig.SecurityOpt}} ro={{.HostConfig.ReadonlyRootfs}} mem={{.HostConfig.Memory}} pids={{.HostConfig.PidsLimit}}'

section "Docker socket and sensitive mounts"
for c in $(docker ps -aq); do
  docker inspect --format '{{.Name}}: {{range .Mounts}}{{.Source}}->{{.Destination}}({{if .RW}}rw{{else}}ro{{end}}) {{end}}' "$c" \
    | grep -E 'docker.sock|/dev/input|/proc|/run/udev|(:| )/->' || true
done

section "Networks"
docker network ls
for n in $(docker network ls --filter driver=bridge -q); do
  docker network inspect --format '{{.Name}} internal={{.Internal}} members={{range .Containers}}{{.Name}} {{end}}' "$n"
done

section "Firewall"
iptables -S DOCKER-USER 2>&1
{ command -v ufw >/dev/null && ufw status verbose || echo "ufw: not installed"; } 2>&1 | head -20
nft list ruleset 2>/dev/null | grep -cE 'drop|reject' | sed 's/^/nft drop-or-reject rules: /'
sysctl net.ipv4.ip_forward net.ipv6.conf.all.disable_ipv6
ip -br addr | grep -v veth
echo "global IPv6 addresses:"; ip -6 addr show scope global | grep -v veth

section "SSH"
sshd -T 2>/dev/null | grep -Ei '^(port|permitrootlogin|passwordauthentication|pubkeyauthentication|kbdinteractiveauthentication|permitemptypasswords|maxauthtries|allowusers|allowgroups|allowtcpforwarding|x11forwarding) '
ps -eo args | grep '[s]shd'
for f in /etc/ssh/sshd_config*; do [ -f "$f" ] && { echo "-- $f"; grep -vE '^\s*(#|$)' "$f"; }; done
echo "-- sftp-access group: $(getent group sftp-access | cut -d: -f4)"
systemctl is-active fail2ban 2>&1 | sed 's/^/fail2ban: /'
fail2ban-client status 2>&1 | head -10
ls /etc/fail2ban/jail.d 2>&1
for f in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys; do
  [ -f "$f" ] && echo "$f: $(grep -cE '^(ssh|ecdsa|sk-)' "$f") keys"
done

section "Other host services"
for s in rpcbind avahi-daemon wsdd smbd nfs-server systemd-resolved; do echo "$s: $(systemctl is-active $s 2>&1)"; done
resolvectl status 2>/dev/null | grep -iE 'llmnr|mdns' | sort -u

section "Accounts"
echo "uid 0: $(awk -F: '$3==0{print $1}' /etc/passwd | tr '\n' ' ')"
echo "docker group: $(getent group docker | cut -d: -f4)"
echo "sudo group: $(getent group sudo | cut -d: -f4)"
echo "empty passwords: $(awk -F: '$2==""{print $1}' /etc/shadow | tr '\n' ' ')"
ls -l /opt/docker/.env /var/run/docker.sock

section "Open or default-credential admin UIs (localhost; HTTP code or response start)"
code() { curl -s -o /dev/null -m 5 -w '%{http_code}' "$@"; }
echo "filebrowser default login admin/hellofilebrowser: $(code -X POST -H 'Content-Type: application/json' -d '{"username":"admin","password":"hellofilebrowser","recaptcha":""}' http://127.0.0.1:8085/files/api/login) (200 = default password still works)"
echo "stash graphql, no login:    $(code -X POST -H 'Content-Type: application/json' -d '{"query":"{systemStatus{status}}"}' http://127.0.0.1:9999/graphql) (200 = no auth)"
echo "fileflows api, no login:    $(code http://127.0.0.1:19200/api/flow) (200 = no auth)"
echo "kodi http jsonrpc:          $(curl -s -m 5 -X POST -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","method":"JSONRPC.Ping","id":1}' http://127.0.0.1:8080/jsonrpc | head -c 60) (pong = no password)"
echo "kodi tcp jsonrpc 9090:      $( { exec 3<>/dev/tcp/127.0.0.1/9090 && printf '{"jsonrpc":"2.0","method":"JSONRPC.Ping","id":1}' >&3 && timeout 2 head -c 60 <&3; } 2>&1 ) (pong = open)"
echo "ums web ui 9001:            $(code http://127.0.0.1:9001/)"
echo "wud containers api:         $(code http://127.0.0.1:3000/api/containers) (200 = no auth)"
echo "gatus statuses:             $(code http://127.0.0.1:8090/api/v1/endpoints/statuses) (200 = no auth)"
echo "jellyfin public users:      $(code http://127.0.0.1:8096/Users/Public) (200 = usernames listed to anyone)"
port=$(grep -E '^PLEX_HTTPS_PORT=' /opt/docker/.env 2>/dev/null | cut -d= -f2); port=${port:-8443}
echo "plex library, no token via nginx: $(code -k "https://127.0.0.1:${port}/library/sections") (200 = Plex treats the proxy as local; expect 401)"

section "Can a container reach the host and LAN? (throwaway alpine on nginx's network)"
net=$(docker inspect nginx --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null | awk '{print $1}')
gw=$(ip route | awk '/default/{print $3; exit}')
bridge_gw=$(docker network inspect "$net" --format '{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null)
echo "network=$net lan_gateway=$gw bridge_gateway=$bridge_gw"
if [ -n "$net" ]; then
  docker run --rm --network "$net" alpine:3.24.2 sh -c "
    for t in $gw:443 $gw:80 $gw:22 $bridge_gw:22 $bridge_gw:8888 $bridge_gw:445; do
      nc -zw2 \${t%:*} \${t#*:} && echo \"reachable: \$t\" || echo \"blocked:   \$t\"
    done"
fi
