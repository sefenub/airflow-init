  NEED
  hostname + DNS record pointing to VM
  signed by internal CA
  Key requirements e.g. RSA 2048 vs 4096, required subject fields
  Inbound firewall rules: 443, 80 for redirect (or)
  ```bash
  mkdir -p certs && chmod 700 certs
  openssl req -new -newkey rsa:2048 -nodes \
    -keyout certs/airflow.key -out certs/airflow.csr \
    -subj "/C=XX/O=Client Org/CN=airflow.client.example" \
    -addext "subjectAltName=DNS:airflow.client.example"
  chmod 600 certs/airflow.key
  echo "certs/" >> .gitignore

  # Check the SAN is in the request
  openssl req -in certs/airflow.csr -noout -text | grep -A1 "Subject Alternative Name"
```

CA may return cert plus one or more intermediate certs
Convert to crt/pem if arrives as .cer (DER) or .p7b

```bash
openssl x509 -inform der -in airflow.cer -out certs/airflow.crt     # DER → PEM
openssl pkcs7 -print_certs -in chain.p7b -out certs/chain.pem        # p7b → PEM

# The cert must match your key (the two hashes must be identical)
openssl x509 -noout -pubkey -in certs/airflow.crt | sha256sum
openssl pkey -pubout -in certs/airflow.key       | sha256sum

# SAN and expiry
openssl x509 -in certs/airflow.crt -noout -ext subjectAltName -enddate

# Your cert first, then the intermediates (root is optional)
cat certs/airflow.crt certs/intermediate.pem > certs/fullchain.pem



openssl s_client -connect airflow.client.example:443 -servername airflow.client.example </dev/null \
  | grep -E "Verify return code|s:|i:"          # expect "Verify return code: 0 (ok)"
curl -fsS https://airflow.client.example/api/v2/monitor/health
curl -sI http://airflow.client.example/ | grep -i location   # expect https://
```
