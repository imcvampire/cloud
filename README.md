# cloud
My personal cloud setup

## Oracle Always Free AdGuard Home

This project creates an Oracle Cloud Always Free, AMD64 VPS (`VM.Standard.E2.1.Micro`), its public network, official Docker CE, and an AdGuard Home stack. It exposes the setup dashboard (TCP 3000), DoH (TCP 443), and DoT (TCP 853); unencrypted DNS port 53 is neither published by Docker nor opened in OCI. SSH is controlled by `admin_cidrs`, the dashboard by `dashboard_cidrs`, and encrypted DNS endpoints by `dns_cidrs`. TCP 80 is also opened for Let's Encrypt certificate issuance and renewal.

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

Open the `setup_dashboard` output and complete AdGuard Home's first-run wizard. Keep the web-interface port set to `3000`, so it stays limited to `dashboard_cidrs`. To enable trusted DoH and DoT, point a DNS hostname (for example `dns.example.com`) at `public_ip`, then configure that hostname and its TLS certificate in AdGuard Home's **Settings → Encryption settings**. Clients should use `https://dns.example.com/dns-query` for DoH and `dns.example.com:853` for DoT. A raw IP cannot provide certificate-valid DoH/DoT.

The host-managed `adguard-update.timer` checks daily at 04:00 UTC by default, pulls and restarts only AdGuard Home, and removes unused images. Change `adguard_update_calendar` with a systemd `OnCalendar` expression to choose another schedule. Since updates are automatic, use a pinned AdGuard image tag instead of `latest` if you prefer a deliberate upgrade cadence.

Oracle sometimes has no free E2 capacity in a chosen availability domain. Set `availability_domain` in `terraform.tfvars` to another domain shown in the OCI console and apply again; this does not need any changes to the infrastructure code.
