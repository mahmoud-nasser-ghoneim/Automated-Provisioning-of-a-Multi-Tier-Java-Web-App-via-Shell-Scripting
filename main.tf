# ---------- read existing objects from VCD ----------
data "vcd_catalog" "cat" {
  org  = "COT-1"
  name = "Eslam"
}

data "vcd_catalog_vapp_template" "ubuntu" {
  org        = "COT-1"
  catalog_id = data.vcd_catalog.cat.id
  name       = "Ubuntu-25-10-live-server"
}

# ---------- the 5 VMs: one entry per VM ----------
locals {
  vms = {
    db01  = { ip = "30.0.0.10", memory = 2048, script = "db.sh" }
    mc01  = { ip = "30.0.0.20", memory = 1024, script = "mc.sh" }
    rmq01 = { ip = "30.0.0.30", memory = 2048, script = "rmq.sh" }
    app01 = { ip = "30.0.0.40", memory = 4096, script = "app.sh" }
    web01 = { ip = "30.0.0.50", memory = 1024, script = "web.sh" }
  }

  # lines for /etc/hosts on every VM, built from the map above
  hosts_block = join("\n", concat(
    ["30.0.0.2 terraform"],
    [for name, vm in local.vms : "${vm.ip} ${name}"]
  ))
}

# ---------- vApp and network ----------
resource "vcd_vapp" "vpro" {
  name        = "nasser-terraform-multi-tier-project"
  description = "vprofile multi-tier project"
}

resource "vcd_vapp_org_network" "net" {
  vapp_name        = vcd_vapp.vpro.name
  org_network_name = "Nasser-test"

  # VCD 10.4.1+ needs the vApp powered off to detach the network on destroy
  reboot_vapp_on_removal = true
}

# ---------- VMs (one resource, five instances) ----------
resource "vcd_vapp_vm" "vm" {
  for_each = local.vms

  vapp_name        = vcd_vapp.vpro.name
  name             = each.key
  computer_name    = each.key
  vapp_template_id = data.vcd_catalog_vapp_template.ubuntu.id
  memory           = each.value.memory
  cpus             = 2
  cpu_cores        = 1

  network {
    type               = "org"
    name               = vcd_vapp_org_network.net.org_network_name
    ip_allocation_mode = "MANUAL"
    ip                 = each.value.ip
    is_primary         = true
  }

  customization {
    enabled = true
    force   = false

    # runs once after the first boot: hosts entries + this VM's script
    initscript = templatefile("${path.module}/scripts/wrapper.tftpl", {
      hosts_block = local.hosts_block
      script_body = file("${path.module}/scripts/${each.value.script}")
    })
  }
}

output "vm_ips" {
  value = { for name, vm in local.vms : name => vm.ip }
}
