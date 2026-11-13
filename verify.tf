# Makes "terraform apply" finish only when the application really answers.
locals {
  site_ip = local.vms["web01"].ip
}

resource "terraform_data" "wait_for_site" {
  depends_on = [vcd_vapp_vm.vm]

  # run the check again if any VM is recreated
  triggers_replace = [for name in sort(keys(local.vms)) : vcd_vapp_vm.vm[name].id]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # the new VMs reuse the old IPs: forget the old SSH host keys
      for ip in ${join(" ", [for vm in values(local.vms) : vm.ip])}; do
        ssh-keygen -R "$ip" >/dev/null 2>&1 || true
      done

      echo "Waiting for http://${local.site_ip}/login (provisioning takes 10-15 minutes) ..."
      for i in $(seq 1 90); do
        code=$(curl -s -o /dev/null -m 10 -w '%%{http_code}' http://${local.site_ip}/login || true)
        if [ "$code" = "200" ]; then
          echo "Site is up: http://${local.site_ip}"
          exit 0
        fi
        echo "  attempt $i/90: HTTP $code - not ready yet"
        sleep 20
      done
      echo "Timed out. Check /var/log/vprofile-provision.log on each VM."
      exit 1
    EOT
  }
}

output "site_url" {
  value = "http://${local.site_ip}"
}
