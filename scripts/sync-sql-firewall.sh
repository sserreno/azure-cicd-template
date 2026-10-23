#!/usr/bin/env bash
# Makes the SQL server's firewall allow exactly the web app's possible
# outbound addresses (docs/adr/0003-sql-with-managed-identity.md). Rules this script owns start with "app-out-";
# other rules (e.g. a pipeline run's temporary one) are left alone.
#
#   scripts/sync-sql-firewall.sh <resource-group> <sql-server> <web-app>
set -euo pipefail

rg="${1:?resource group}"; server="${2:?sql server}"; app="${3:?web app}"

mapfile -t wanted < <(az webapp show --resource-group "$rg" --name "$app" \
  --query possibleOutboundIpAddresses --output tsv | tr ',' '\n' | sed '/^$/d' | sort -u)
[[ ${#wanted[@]} -gt 0 ]] || { echo "no outbound addresses found for $app" >&2; exit 1; }

mapfile -t existing < <(az sql server firewall-rule list --resource-group "$rg" --server "$server" \
  --query "[?starts_with(name, 'app-out-')].name" --output tsv)

declare -A keep=()
for ip in "${wanted[@]}"; do
  name="app-out-${ip//./-}"
  keep[$name]=1
  if ! printf '%s\n' "${existing[@]}" | grep -qx "$name"; then
    az sql server firewall-rule create --resource-group "$rg" --server "$server" \
      --name "$name" --start-ip-address "$ip" --end-ip-address "$ip" --output none
    echo "allowed $ip"
  fi
done

for name in "${existing[@]}"; do
  [[ -n "$name" && -z "${keep[$name]:-}" ]] || continue
  az sql server firewall-rule delete --resource-group "$rg" --server "$server" --name "$name" --output none
  echo "removed $name"
done
