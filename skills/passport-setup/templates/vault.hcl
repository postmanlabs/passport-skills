# Secret Vault (HashiCorp) for a local Passport setup: one node, data on a Docker volume,
# web UI on (reached through a 127.0.0.1-only port), no TLS inside Docker.
ui            = true
disable_mlock = true
api_addr      = "http://127.0.0.1:8200"

storage "file" {
  path = "/vault/file"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}
