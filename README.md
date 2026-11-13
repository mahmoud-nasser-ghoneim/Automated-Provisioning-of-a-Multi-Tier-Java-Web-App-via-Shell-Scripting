# Automated Provisioning of a Multi-Tier Java Web App via Shell Scripting

Terraform + shell scripts that build the vprofile multi-tier Java application on
**VMware Cloud Director (VCD)** with a single command. Terraform creates the vApp
and five Ubuntu VMs; each VM configures its own tier at first boot using a shell
script delivered through VCD guest customization. The run finishes only when the
web site answers.

## Architecture

```
User -> web01 (Nginx :80) -> app01 (Tomcat :8080) -> db01  (MariaDB   :3306)
                                                   -> mc01  (Memcached :11211)
                                                   -> rmq01 (RabbitMQ  :5672)
```

| VM    | Role                 | IP         | RAM  | Script           |
|-------|----------------------|------------|------|------------------|
| db01  | MariaDB (database)   | 30.0.0.10  | 2 GB | `scripts/db.sh`  |
| mc01  | Memcached (cache)    | 30.0.0.20  | 1 GB | `scripts/mc.sh`  |
| rmq01 | RabbitMQ (queue)     | 30.0.0.30  | 2 GB | `scripts/rmq.sh` |
| app01 | Tomcat (application) | 30.0.0.40  | 4 GB | `scripts/app.sh` |
| web01 | Nginx (web)          | 30.0.0.50  | 1 GB | `scripts/web.sh` |

The Terraform host is `30.0.0.2` on the same network (`Nasser-test`, 30.0.0.1/24).

## Repository layout

```
.
├── deploy.sh                  # one command: init -> validate -> apply -> wait for the site
├── destroy.sh                 # remove everything Terraform created
├── main.tf                    # catalog/template lookup, vApp, network, the 5 VMs (for_each)
├── verify.tf                  # waits until http://<web01>/login answers
├── provider.tf                # VCD provider and connection settings
├── variables.tf               # vcd_user, vcd_password
├── terraform.tfvars.example   # copy to terraform.tfvars and fill in
├── .terraform.lock.hcl        # pins the provider version
└── scripts/
    ├── wrapper.tftpl          # first-boot wrapper: /etc/hosts + runs the VM's script
    └── db.sh  mc.sh  rmq.sh  app.sh  web.sh
```

## Prerequisites

- A VCD account with rights to create vApps and VMs in the target VDC.
- A Terraform host on the same network as the VMs, with Terraform >= 1.4
  (uses `terraform_data`), `git` and `curl`.
- In VCD: a catalog containing an Ubuntu vApp template, and an org network with a
  static IP pool that covers 30.0.0.10 - 30.0.0.50 and outbound internet access
  (the VMs install packages and download the application at first boot).
- Names used in `main.tf` (edit them for your environment): org/VDC `COT-1`,
  catalog `Eslam`, template `Ubuntu-25-10-live-server`, network `Nasser-test`.

## Quick start

```bash
git clone <this-repo-url> && cd <repo-folder>
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars          # put your real VCD user and password (file is git-ignored)
./deploy.sh                    # or ./deploy.sh -y to skip the confirmation
```

`deploy.sh` runs `terraform init`, `validate` and `apply`. The apply:

1. creates the vApp and attaches the network,
2. creates the five VMs and applies hostname and IP with guest customization,
3. lets every VM run its tier script in the background (about 10-25 minutes),
4. waits until `http://30.0.0.50/login` returns HTTP 200, then prints the URL.

To run it detached from your SSH session:

```bash
nohup ./deploy.sh -y > deploy.log 2>&1 &
tail -f deploy.log
```

## How the provisioning works

- `wrapper.tftpl` is rendered by Terraform for each VM and passed as the guest
  customization `initscript`. After the first boot it adds the `/etc/hosts`
  entries for all VMs, saves the VM's tier script to `/root/provision.sh`, and
  starts it with `systemd-run` so long installs do not block the customization.
- Every tier script waits for internet access, installs its packages, applies its
  configuration, and logs to `/var/log/vprofile-provision.log`.
- `app.sh` waits for `db01:3306`, `mc01:11211` and `rmq01:5672` before building
  and deploying the application, because all VMs are provisioned in parallel.
- VMware documents a limit of 1500 characters for the guest customization script.
  On the VCD version used here, the ~3 KB script for `app01` was delivered and ran
  to completion. If your VCD enforces the limit, customization will not run the
  script and the VMs will not be provisioned; in that case keep the `initscript`
  tiny (hosts, SSH key, sudo) and run the tier scripts from Terraform over SSH
  (`file` + `remote-exec` provisioners) instead.

## Verify

Open `http://30.0.0.50` and log in with the sample user from the project's data
(`admin_vp`). The **All Users** button exercises Memcached and **RabbitMq**
exercises the queue. The **Elasticsearch** button will not work: Elasticsearch is
part of the original architecture but is not installed here.

## Troubleshooting

| Symptom | Check |
|---|---|
| `deploy.sh` times out waiting for the site | On each VM: `sudo tail -n 50 /var/log/vprofile-provision.log` and `systemctl status vprofile-provision` |
| `/root/provision.sh` does not exist on a VM | Guest customization did not run the script: see `/var/log/vmware-imc/` |
| `502 Bad Gateway` from Nginx | Tomcat on `app01` is still building or failed: `sudo journalctl -u tomcat -n 50` |
| `/login` returns 404 | The application failed to start: look for `Caused by` in the Tomcat journal |
| `ssh` says the host key changed | The new VMs reuse old IPs: `ssh-keygen -R <ip>` (`deploy.sh` does this for you) |

Running `./deploy.sh` again after a failed wait only retries the wait; it does not
recreate the VMs.

## Destroy

```bash
./destroy.sh        # or ./destroy.sh -y
```

The vApp network is configured with `reboot_vapp_on_removal = true` because VCD
10.4.1+ requires the vApp to be powered off to detach a network.

## Differences from the original CentOS/Java 11 guide

- `apt` replaces `yum`/`dnf`.
- MariaDB and Memcached listen on localhost by default on Ubuntu, so the scripts
  set `bind-address` / `-l` to `0.0.0.0`.
- The application is old and fails on Java 17 without the `--add-opens` flags in
  `CATALINA_OPTS` (`InaccessibleObjectException` otherwise).
- `sudo mysql` uses socket authentication, so there is no `mysql_secure_installation`
  step, and no firewall configuration (`ufw` is inactive on these images).

## Security notes

- `terraform.tfvars`, the Terraform state and the `.terraform/` folder are
  git-ignored. Never commit them.
- Passwords such as `admin123` and `test/test` are lab defaults from the original
  project. Change them for anything beyond a lab.
- Keep this repository private: it contains internal IP addresses and VCD names.
