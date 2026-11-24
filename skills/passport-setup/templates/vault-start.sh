#!/bin/sh
# Container start command for the local HashiCorp Vault: start the server, then
# unlock it with the key the skill saved, so a restart or reboot never leaves it
# locked. Before the first init there is no key yet; the skill initialises Vault.
vault server -config=/vault/config/vault.hcl &
pid=$!
key=/vault/unseal/unseal-key
i=0
while [ "$i" -lt 60 ]; do
  vault status >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 0 ] && break
  if [ "$rc" -eq 2 ]; then
    [ -s "$key" ] || break
    vault operator unseal "$(cat "$key")" >/dev/null 2>&1 && break
  fi
  i=$((i + 1))
  sleep 1
done
wait "$pid"
