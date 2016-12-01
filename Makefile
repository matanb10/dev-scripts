SRC_ROOT=/images/SOURCE
KERNEL_SRC=$(SRC_ROOT)/upstream_fun
# VMware
VMWARE_VM=$(SRC_ROOT)/src/vm-machines/archlinux/archlinux.vmx
VMWARE_VM_REPACK=$(SRC_ROOT)/src/vm-machines/archlinux/archlinux-000001.vmdk

# KVM
#KVM_RELEASE=wheezy
#KVM_RELEASE=jessie
KVM_RELEASE=sid
KVM_PACKAGES=openssh-server,python,perl,vim,pciutils,ibverbs-utils,libibverbs-dev,libmlx5-dev,infiniband-diags,opensm,librdmacm-dev,rdmacm-utils,libnl-3-200,libnl-route-3-200
KVM_SHARED=$(SRC_ROOT)/kvm_shared
KVM_SHARED_USER=$(KVM_SHARED)/usr
KVM_SHARED_MODULES=$(KVM_SHARED)/modules
KVM_IMAGE=$(SRC_ROOT)/dev-scripts/build

# SimX
#SIMX_BIN=$(SRC_ROOT)/simx_bin/bin/qemu-system-x86_64
SIMX_BIN=$(SRC_ROOT)/simx/x86_64-softmmu/qemu-system-x86_64

# LIBS
LIBIBVERBS_SRC=$(SRC_ROOT)/libibverbs/
LIBMLX5_SRC=$(SRC_ROOT)/libmlx5/

# Strace
STRACE_SRC=$(SRC_ROOT)/strace-code/

ssh:
	@ssh root@localhost -p4444

kvm:
	@echo "Start KVM image"
	@# add -s option for running gdb
	@# and run "ggb vmlinux"
	@kvm -kernel $(KERNEL_SRC)/arch/x86_64/boot/bzImage -drive \
		file=$(KVM_IMAGE)/$(KVM_RELEASE).img,if=virtio,format=raw \
		-append 'root=/dev/vda console=hvc0 debug rootwait rw' \
		-chardev stdio,id=stdio,mux=on,signal=off \
		-device virtio-serial-pci \
		-device virtconsole,chardev=stdio \
		-mon chardev=stdio \
		-display none \
		-net nic,model=virtio,macaddr=52:54:00:12:34:56 \
		-net user,hostfwd=tcp:127.0.0.1:4444-:22 \
		-fsdev local,id=fs1,path=/images/SOURCE,security_model=passthrough \
		-device virtio-9p-pci,fsdev=fs1,mount_tag=host-code
simx:
	@echo "Start SimX image"
	@# add -s option for running gdb
	@# and run "ggb vmlinux"
	@$(SIMX_BIN) -enable-kvm -kernel $(KERNEL_SRC)/arch/x86/boot/bzImage -drive \
		file=$(KVM_IMAGE)/$(KVM_RELEASE).img,if=virtio,format=raw \
		-no-reboot -nographic \
		-m 512M -append 'root=/dev/vda console=hvc0 debug rootwait rw' \
		-chardev stdio,id=stdio,mux=on,signal=off \
		-device virtio-serial-pci \
		-device virtconsole,chardev=stdio \
		-mon chardev=stdio \
		-display none \
		-net nic,model=virtio,macaddr=52:54:00:12:34:56 \
		-net user,hostfwd=tcp:127.0.0.1:4444-:22 \
		-netdev tap,fd=26,id=hostnet0 -device e1000,netdev=hostnet0,id=net0,mac=00:50:56:18:25:09 \
		-netdev tap,fd=28,id=hostnet1 -device connectx4,netdev=hostnet1,id=net1,mac=52:54:00:b5:47:32 \
		-fsdev local,id=fs1,path=$(SRC_ROOT),security_model=passthrough \
		-device virtio-9p-pci,fsdev=fs1,mount_tag=host-code \
		-fsdev local,id=fs2,path=$(KVM_SHARED_USER),security_model=passthrough \
		-device virtio-9p-pci,fsdev=fs2,mount_tag=user \
		-fsdev local,id=fs3,path=$(KVM_SHARED_MODULES),security_model=passthrough \
		-device virtio-9p-pci,fsdev=fs3,mount_tag=modules

kvm-prepare-folder:
	@echo "Build Debian $(KVM_RELEASE) image"
	@sudo rm -rf build
	@mkdir -p build/kvm-image
	@sudo debootstrap --include=$(KVM_PACKAGES) $(KVM_RELEASE) build/kvm-image http://http.debian.net/debian/
	@sudo sed -i '/^root/ { s/:x:/::/ }' build/kvm-image/etc/passwd
	@echo 'V0:23:respawn:/sbin/getty 115200 hvc0' | sudo tee -a build/kvm-image/etc/inittab
	@printf '\nauto eth0\niface eth0 inet dhcp\n' | sudo tee -a build/kvm-image/etc/network/interfaces
	@printf '\nMaxLevelConsole=crit\n' | sudo tee -a build/kvm-image/etc/systemd/journald.conf
	@echo 1
	@sudo mkdir build/kvm-image/root/.ssh/
	@sudo mkdir build/kvm-image/home/code
	@sudo mkdir build/kvm-image/lib/modules
	@echo 2
	@sudo rm -rf build/kvm-image/usr/local/*
	@echo 3
	@printf 'host-code /home/code 9p defaults 0 0\nuser /usr/local 9p defaults 0 0\nmodules /lib/modules 9p defaults 0 0\n' | sudo tee -a build/kvm-image/etc/fstab
	@echo 4
	@cat ~/.ssh/id_?sa.pub | sudo tee build/kvm-image/root/.ssh/authorized_keys

kvm-make-img:
	@dd if=/dev/zero of=build/$(KVM_RELEASE).img bs=1M seek=4095 count=1
	@mkfs.ext4 -F build/$(KVM_RELEASE).img
	@sudo mkdir -p build/mnt-$(KVM_RELEASE)
	@sudo mount -o loop build/$(KVM_RELEASE).img build/mnt-$(KVM_RELEASE)
	@sudo cp -a build/kvm-image/. build/mnt-$(KVM_RELEASE)/.
	@sudo umount build/mnt-$(KVM_RELEASE)
	@sudo rm -rf build/mnt-$(KVM_RELEASE)
	@echo "Image was built successfuly"

kvm-image: kvm-prepare-folder kvm-make-img

clean-kvm-image:
	@sudo rm -rf build/$(KVM_RELEASE).img build/mnt-$(KVM_RELEASE) build/kvm-image

vmware-config:
	@cp configs/vmware-config $(KERNEL_SRC)/.config

kvm-config:
	@cp configs/kvm-config $(KERNEL_SRC)/.config

clean-shared:
	@rm -rf $(KVM_SHARED)/*

libs:
	@echo "Build libibverbs"
	@cd $(LIBIBVERBS_SRC)/; ./autogen.sh; ./configure --prefix=$(KVM_SHARED_USER) --sysconfdir=/etc CFLAGS=-I$(KVM_SHARED_USER)/include LDFLAGS=-L$(KVM_SHARED_USER)/lib CPPFLAGS=-I$(KVM_SHARED_USER)/include; $(MAKE); $(MAKE) install
	@echo "Build libmlx5"
	@cd $(LIBMLX5_SRC)/; ./autogen.sh; ./configure --prefix=$(KVM_SHARED_USER) CFLAGS=-I$(KVM_SHARED_USER)/include LDFLAGS=-L$(KVM_SHARED_USER)/lib CPPFLAGS=-I$(KVM_SHARED_USER)/include; $(MAKE); $(MAKE) install

build:
	@echo "Start kernel build"
	@make -C $(KERNEL_SRC) oldconfig
	@make -C $(KERNEL_SRC) -j8

khi:
	@echo "Install kernel headers"
	@make -C $(KERNEL_SRC) headers_install INSTALL_HDR_PATH=$(KVM_SHARED_USER)

modules_install:
	@cd $(KERNEL_SRC)/; make modules_install INSTALL_MOD_PATH=$(KVM_SHARED_MODULES)

strace:
	@cd $(STRACE_SRC)/; ./bootstrap; ./configure --prefix=$(KVM_SHARED) CFLAGS=-I$(KVM_SHARED)/include LDFLAGS=-L$(KVM_SHARED)/lib CPPFLAGS=-I$(KVM_SHARED)/include; $(MAKE); $(MAKE) install

shared: clean-shared khi strace libs

scp:
	@ssh -p4444 root@localhost "rm -rf /home/leonro/src/kvm-shared"
	@scp -r -P4444 /home/leonro/src/kvm-shared  root@localhost:/home/leonro/src/

test:
	@ssh -p4444 root@localhost "/home/leonro/src/kvm-shared/bin/ibv_devinfo"

stop-vmware-vm:
	@echo "Stop VMware VM"
	@vmrun stop $(VMWARE_VM)

start-vmware-vm:
	@echo "Start VMware VM"
	@vmrun start $(VMWARE_VM)

update-vmware-vm:
	@echo "Patch boot partition"
	@mkdir -p build
	@mkdir -p build/vmware
	@vmware-mount $(VMWARE_VM_REPACK) build/vmware
	@sudo cp -v $(KERNEL_SRC)/arch/x86/boot/bzImage build/vmware/vmlinuz-linux-dev
	@sudo cp -v $(KERNEL_SRC)/System.map build/vmware
	@vmware-mount -d build/vmware
	@rmdir -rf build/vmware

vmware-vm: stop-vmware-vm update-vmware-vm start-vmware-vm

all:
	@echo "Do nothing!!!!!"
