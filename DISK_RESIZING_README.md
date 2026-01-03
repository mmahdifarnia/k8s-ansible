# Kubernetes Node Disk Resizing Guide

## Problem Description

In Vagrant-based Kubernetes clusters, you might encounter a situation where:
- VirtualBox shows the VM has 30GB or 50GB disk space
- But `df -h` shows only ~10GB available space
- This causes pod evictions due to "DiskPressure" when disk usage reaches 75%

## Root Cause

The issue occurs because:
1. `vb.memory` and `vb.cpus` in Vagrantfile apply immediately
2. `vm.disk` setting creates the virtual disk but doesn't resize the internal LVM volumes
3. The LVM logical volume remains at the original size (usually 10GB) even though the virtual disk is larger

## Solution: Resize LVM Volumes

### Step 1: Check Current Disk Layout

Check the current disk structure on each node:

```bash
vagrant ssh [node-name] -c "lsblk"
```

Example output:
```
NAME                      MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
sda                         8:0    0   30G  0 disk
├─sda1                      8:1    0  931M  0 part /boot/efi
├─sda2                      8:2    0  1.8G  0 part /boot
└─sda3                      8:3    0 16.9G  0 part
  └─ubuntu--vg-ubuntu--lv 252:0    0   10G  0 lvm  /
```

### Step 2: Verify Disk Usage

Check current filesystem usage:

```bash
vagrant ssh [node-name] -c "df -h /"
```

Example output (before fix):
```
Filesystem                         Size  Used Avail Use% Mounted on
/dev/mapper/ubuntu--vg-ubuntu--lv   9.8G  7.4G  2.0G  79% /
```

### Step 3: Resize Physical Volume

Expand the physical volume to use the full partition space:

```bash
vagrant ssh [node-name] -c "sudo pvresize /dev/sda3"
```

Expected output:
```
Physical volume "/dev/sda3" changed
1 physical volume(s) resized or updated / 0 physical volume(s) not resized
```

### Step 4: Extend Logical Volume

Extend the logical volume to use all available space in the volume group:

```bash
vagrant ssh [node-name] -c "sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv"
```

Expected output:
```
Size of logical volume ubuntu-vg/ubuntu-lv changed from 10.00 GiB (2560 extents) to <16.87 GiB (4318 extents).
Logical volume ubuntu-vg/ubuntu-lv successfully resized.
```

### Step 5: Resize Filesystem

Resize the ext4 filesystem to use the expanded logical volume:

```bash
vagrant ssh [node-name] -c "sudo resize2fs /dev/ubuntu-vg/ubuntu-lv"
```

Expected output:
```
resize2fs 1.47.0 (5-Feb-2023)
Filesystem at /dev/ubuntu-vg/ubuntu-lv is mounted on /; on-line resizing required
old_desc_blocks = 2, new_desc_blocks = 3
The filesystem on /dev/ubuntu-vg/ubuntu-lv is now 4421632 (4k) blocks long.
```

### Step 6: Verify the Changes

Confirm the disk space has been expanded:

```bash
vagrant ssh [node-name] -c "df -h /"
```

Expected output (after fix):
```
Filesystem                         Size  Used Avail Use% Mounted on
/dev/mapper/ubuntu--vg-ubuntu--lv   17G  7.4G  8.8G  46% /
```

## Automated Commands for All Nodes

### For Master Node:
```bash
vagrant ssh k8s-master -c "sudo pvresize /dev/sda3 && sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv && sudo resize2fs /dev/ubuntu-vg/ubuntu-lv"
```

### For Worker1:
```bash
vagrant ssh k8s-worker1 -c "sudo pvresize /dev/sda3 && sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv && sudo resize2fs /dev/ubuntu-vg/ubuntu-lv"
```

### For Worker2:
```bash
vagrant ssh k8s-worker2 -c "sudo pvresize /dev/sda3 && sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv && sudo resize2fs /dev/ubuntu-vg/ubuntu-lv"
```

## Results

### Before Fix:
- **Disk Size:** 10GB total
- **Available:** ~2GB
- **Usage:** 75-80%
- **Result:** Pod evictions due to DiskPressure

### After Partial Fix (LVM expansion):
- **Disk Size:** 17GB total
- **Available:** ~9GB
- **Usage:** 42-46%
- **Result:** No more disk pressure issues

### After Full Fix (Partition expansion):
- **Disk Size:** 27GB total
- **Available:** ~19GB
- **Usage:** 26%
- **Result:** Ample disk space, future-proofed

## Prevention

1. **Vagrantfile Configuration:**
   ```ruby
   node_vm.vm.disk :disk, size: "50GB", primary: true
   ```

2. **Monitor Disk Usage:**
   ```bash
   kubectl top nodes
   kubectl describe nodes | grep DiskPressure
   ```

3. **Regular Maintenance:**
   ```bash
   # Clean systemd journals
   sudo journalctl --vacuum-size=50M

   # Check disk usage
   df -h /
   ```

## Troubleshooting

### If Commands Fail:
- Ensure you're running with `sudo`
- Check that the device names are correct (`lsblk`)
- Verify the volume group name (`vgdisplay`)

### If Space Still Limited:
- The virtual disk might be smaller than expected
- Consider recreating VMs with larger disk allocation
- Check VirtualBox VM settings

## Advanced: Full Disk Utilization

If you notice that partition sizes still don't add up to the total disk size, there may be unpartitioned space. To use **all** available disk space:

### Step 1: Check for Unpartitioned Space
```bash
sudo parted /dev/sda print
```
Look for the warning: "Not all of the space available to /dev/sda appears to be used"

### Step 2: Resize the LVM Partition
```bash
sudo parted /dev/sda resizepart 3 100%
```

### Step 3: Expand LVM and Filesystem
```bash
sudo pvresize /dev/sda3
sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
sudo resize2fs /dev/ubuntu-vg/ubuntu-lv
```

### Result:
- **Before:** 17GB usable (from 30GB disk)
- **After:** 27GB usable (full disk utilization)

## Notes

- This process is safe and doesn't require downtime
- All data is preserved during the resize
- The resize happens online (filesystem remains mounted)
- After resizing, you may need to clean up logs to further free space
- For maximum space utilization, check for unpartitioned gaps with `parted`
