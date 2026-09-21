# cloud
My personal cloud setup

## Oracle Always Free hosts

This project creates two Always Free hosts sharing one VCN, internet gateway, and route table, each in its own subnet:

| Host | Shape | Default size | Runs |
|------|-------|--------------|------|
| `amd64-1` | `VM.Standard.E2.1.Micro` | 1/8 OCPU, 1 GB | Docker CE and an AdGuard Home stack |
| `arm64-1` | `VM.Standard.A1.Flex` | 1 OCPU, 6 GB | Docker CE only (opt-in) |

`arm64-1` is opt-in and **not created by default**. Set `create_arm64 = true` to build it; the toggle covers the instance, its subnet, and its security list, and leaves `amd64-1` untouched either way.

They sit in separate subnets rather than sharing one and separating them with a network security group. OCI applies the **union** of a VNIC's subnet security lists and its NSGs, so a shared subnet would grant `arm64-1` the AdGuard ingress as well. Separate subnets are what keeps the two rule sets disjoint.

Both hosts get the same base treatment: a swap file created before the first package upgrade, `sshd` with `OOMScoreAdjust=-900`, and Docker CE from Docker's own repository. `scripts/install-docker-ce.sh` is the single copy of that installer, read by both cloud-init templates; it resolves the architecture from `dpkg`, so one script serves amd64 and arm64.

### AdGuard Home on amd64-1

Unencrypted DNS port 53 is neither published by Docker nor opened in OCI.

Ingress is split by who needs to reach each port:

| Port | Purpose | Controlled by | Path |
|------|---------|---------------|------|
| 22 | SSH | `admin_cidrs` | Direct to origin |
| 3000 | Setup dashboard | `dashboard_cidrs` | Direct to origin |
| 80, 443 | DoH and certificate validation | Cloudflare edge ranges, fetched at plan time | Through Cloudflare |
| 853 | DoT | `dot_cidrs`, empty by default | Direct to origin |

Because 80 and 443 accept Cloudflare's published ranges only, the origin cannot be used as an open resolver and is not reachable for DoH at its IP address. The ranges come from `https://www.cloudflare.com/ips-v4` during `tofu plan`, so the security list and AdGuard's `trusted_proxies` are generated from one source and cannot drift apart. A postcondition fails the plan if that list is unreachable or truncated, rather than applying an empty rule set that would lock out every client.

Prerequisites: an OCI account/API signing key, an SSH public key, and [mise](https://mise.jdx.dev/).

Create your local input file before either deployment:

```sh
mise install
cp terraform.tfvars.example terraform.tfvars
```

### Remote state (recommended)

State is stored in a private, versioned OCI **Standard** Object Storage bucket. Standard storage is included in OCI Always Free up to 10 GB and is appropriate for state because it is immediately available; Archive storage is not appropriate for a backend.

First create the bucket locally, using the OCI API-key values entered in `terraform.tfvars`:

```sh
mise install
tofu -chdir=bootstrap init
tofu -chdir=bootstrap apply -var-file=../terraform.tfvars
```

In the OCI Console, open **Profile → Customer secret keys**, create a key, and copy both its access key and secret. Store them in a local `~/.aws/credentials` profile (never in this repository):

```ini
[oci-tofu]
aws_access_key_id = your-customer-secret-access-key
aws_secret_access_key = your-customer-secret
```

Set restrictive permissions and select that profile and the bucket's region:

```sh
chmod 600 ~/.aws/credentials
export AWS_PROFILE=oci-tofu
export AWS_REGION=eu-frankfurt-1
```

Copy `state.backend.hcl.example` to `state.backend.hcl`, replace `YOUR_OBJECT_STORAGE_NAMESPACE` with the `object_storage_namespace` bootstrap output, and set its region and bucket name if you changed the examples. Then initialize the root project and migrate its state:

```sh
mise install
cp state.backend.hcl.example state.backend.hcl
tofu init -backend-config=state.backend.hcl
tofu fmt -check
tofu validate
tofu apply
```

The S3-compatible backend has no distributed lock configured here, so do not run OpenTofu concurrently against this state.

If backend initialization reports `SignatureDoesNotMatch`, confirm that `state.backend.hcl` has the exact bucket region and endpoint region (both must match the bucket), and that its `profile` matches the Customer Secret Key profile. Then retry with:

```sh
AWS_PROFILE=oci-tofu AWS_REGION=eu-frankfurt-1 tofu init -reconfigure -backend-config=state.backend.hcl
```

An OCI API-signing key cannot authenticate this backend: it requires the **Customer Secret Key** belonging to a user permitted to manage objects in the bucket. If the secret was not saved when it was created, delete that Customer Secret Key in OCI and create a new one; OCI only displays the secret once.

### Cloudflare in front

Set this up **before** applying the Cloudflare-only ingress, or DoH stops working the moment the security list changes.

In Cloudflare DNS, create a proxied (orange cloud) `A` record for your chosen hostname pointing at the `public_ip` output, and set `dns_hostname` in `terraform.tfvars` to match. Set SSL/TLS mode to **Full (strict)**. Issue a Cloudflare **Origin CA** certificate and install it in AdGuard Home under **Settings → Encryption settings** with that hostname as the server name. An Origin CA certificate is valid for fifteen years and is trusted by Cloudflare rather than by browsers, which removes the need for ACME and lets you close TCP 80 by dropping `80` from `cloudflare_origin_ports` in `main.tf`.

Clients then use `https://dns.example.com/dns-query` for DoH.

Two consequences are worth accepting deliberately. Cloudflare terminates TLS, so every DNS query traverses their edge in plaintext; this protects the origin from scanning and abuse, but it does not keep your queries private from Cloudflare. And Cloudflare's proxy carries HTTP and HTTPS only, so **TCP 853 cannot traverse it on any standard plan**. DoT therefore bypasses Cloudflare entirely and requires `dot_cidrs`, which only works for clients at a stable address. Android's Private DNS is DoT-only, so Android clients need either `dot_cidrs` or a DoH-capable client.

Open the `setup_dashboard` output and complete AdGuard Home's first-run wizard. Keep the web-interface port set to `3000`, so it stays limited to `dashboard_cidrs`.

### Sizing and stability on amd64-1

`VM.Standard.E2.1.Micro` is **1/8 OCPU and 1 GB**, not a full OCPU. A 1 GB host with no swap livelocks when an apt run and a container image pull overlap: the kernel keeps completing TCP handshakes while no userspace process can be scheduled, so the host accepts SSH connections but never returns a banner. The configuration guards against this in four places:

- A `swap_size_gb` swap file, created by cloud-init's mounts module before packages are upgraded and before Docker is installed, absorbs the allocation burst.
- `adguard-update.timer` sets `Persistent=false` and `RandomizedDelaySec=1h`. With `Persistent=true` a missed nightly run fires the instant the host boots, stacking an image pull on top of first-boot apt activity, which turns every reboot into the same failure.
- The container has a hard `adguard_memory_limit` and rotated logs, so it cannot exhaust the host or the disk.
- `sshd` runs with `OOMScoreAdjust=-900`, so it survives memory pressure and the host stays recoverable over SSH instead of needing a serial console.

`ignore_changes` on `user_data` means edits here reach a **new** instance only. Apply them to a running host over SSH, or rebuild deliberately.

For real headroom, `VM.Standard.A1.Flex` is also Always Free at 2 OCPU and 12 GB (halved from 4/24 on 15 June 2026). It is arm64, and the AdGuard image is multi-arch, so moving AdGuard there changes only `instance_shape`, `instance_ocpus`, and `instance_memory_gbs`. If `create_arm64` is on, `arm64-1` already holds half the A1 allowance, so either shrink `arm64_instance_ocpus` and `arm64_instance_memory_gbs` further or turn it off before sizing AdGuard onto A1.

The host-managed `adguard-update.timer` checks daily at 04:00 UTC by default, spread by up to an hour, pulls and restarts only AdGuard Home, and removes unused images. Change `adguard_update_calendar` with a systemd `OnCalendar` expression to choose another schedule. Since updates are automatic, use a pinned AdGuard image tag instead of `latest` if you prefer a deliberate upgrade cadence.

### The arm64 host

Off unless `create_arm64 = true`. `arm64-1` is a bare Docker host: `cloud-init-base.yaml.tftpl` installs Docker CE, adds `ubuntu` to the `docker` group, creates swap, and hardens `sshd` against the OOM killer. It deploys no application, publishes no ports, and has no update timer, because nothing on it is managed from here.

Its only ingress is SSH from `admin_cidrs`, plus ICMP type 3 code 4 so Path MTU Discovery keeps working. Opening a port for something you deploy later means adding a rule to `oci_core_security_list.arm64`; adding it to the AdGuard list has no effect on this host.

```sh
tofu output arm64_ssh
```

Two constraints worth knowing before enabling it. The Always Free A1 allowance is **2 OCPU and 12 GB in total** across every A1 instance in the tenancy, and `arm64_instance_ocpus`/`arm64_instance_memory_gbs` take half of it, leaving room for one more A1 instance. Free A1 capacity is also frequently exhausted in a given availability domain while available in another, which is why `arm64_availability_domain` is set separately from the AdGuard host rather than following it.

`ignore_changes` on `user_data` applies here too, so edits to `cloud-init-base.yaml.tftpl` reach a new instance only.

Turning `create_arm64` back off after an apply is a destroy, not a pause: the instance and its boot volume go with it. Stop the instance in the OCI console instead if you only want it powered off.

Oracle sometimes has no free E2 capacity in a chosen availability domain. Set `availability_domain` in `terraform.tfvars` to another domain shown in the OCI console and apply again; this does not need any changes to the infrastructure code.
