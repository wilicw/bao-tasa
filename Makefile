pwd:=$(shell pwd)
PLATFORM?=rpi4
ARCH:=aarch64
freertos:=freertos-over-bao
buildroot:=buildroot
proc:=$(shell nproc)
build_dir:=$(pwd)/build
linux:=linux
lloader:=lloader
uboot:=u-boot
TFA:=TFA
bao:=bao-hypervisor
firmware:=firmware
baremetal:=bao-baremetal-guest

export LINUX_OVERRIDE_SRCDIR=$(pwd)/$(linux)
export BAO_DEMOS_LINUX_CFG_FRAG=$(pwd)/configs/linux/base.config $(pwd)/configs/linux/$(ARCH).config $(pwd)/configs/linux/$(PLATFORM).config
export CROSS_COMPILE=aarch64-none-elf-
BAREMETAL_PARAMS:=""

init:
	mkdir -p $(build_dir)

freertos: init $(freertos)/
	$(MAKE) -C $(pwd)/$(freertos) PLATFORM=$(PLATFORM) ARCH_CPPFLAGS=-Og -j$(proc)
	cp $(pwd)/$(freertos)/build/$(PLATFORM)/freertos.bin $(build_dir)

linux: init $(linux)/ $(buildroot)/
	# Build buildroot
	$(MAKE) -C $(pwd)/$(buildroot) defconfig BR2_DEFCONFIG=$(pwd)/configs/buildroot/$(ARCH).config -j$(proc)
	# Build Kernel
	-$(MAKE) -C $(pwd)/$(buildroot) linux-reconfigure all
	cp $(pwd)/$(buildroot)/output/images/Image $(build_dir)

wrap_linux: linux
	# Compile device tree
	dtc $(pwd)/devicetrees/linux.dts > $(build_dir)/linux.dtb
	# Link
	$(MAKE) -C $(pwd)/$(lloader) ARCH=$(ARCH) IMAGE=$(build_dir)/Image DTB=$(build_dir)/linux.dtb TARGET=$(build_dir)/linux

rasp: init $(TFA)/ $(firmware)/ $(uboot)/
	$(MAKE) -C $(pwd)/$(uboot) rpi_4_defconfig
	$(MAKE) -C $(pwd)/$(uboot) -j$(proc)
	cp $(pwd)/$(uboot)/u-boot.bin $(build_dir)/
	$(MAKE) -C $(pwd)/$(TFA) PLAT=$(PLATFORM) -j$(proc)
	cp $(pwd)/$(TFA)/build/$(PLATFORM)/release/bl31.bin $(build_dir)

bao:
	make -C $(pwd)/$(bao) clean
	make -C $(pwd)/$(bao)\
		PLATFORM=$(PLATFORM)\
		CONFIG_REPO=$(pwd)/configs/bao-configs/$(OS)\
		CONFIG=$(PLATFORM)\
    CPPFLAGS=-DBAO_DEMOS_WRKDIR_IMGS=$(build_dir)\
		-j$(proc)
	cp $(pwd)/$(bao)/bin/$(PLATFORM)/$(PLATFORM)/bao.bin $(build_dir)

pack:
	cp -rf $(pwd)/$(firmware)/boot/* $(build_dir)
	cp $(pwd)/configs/config.txt $(build_dir)
	rm -f $(pwd)/build.zip
	cd $(build_dir) && zip -r $(pwd)/build.zip ./*

patches:
	-cd $(pwd)/$(freertos)/src/baremetal-runtime &&\
		git switch demo &&\
		git pull --depth 1 &&\
		git apply $(pwd)/patches/freertos/drivers/*.patch
	-cd $(pwd)/$(freertos) &&\
		git switch demo &&\
		git pull --depth 1 &&\
		git apply $(pwd)/patches/freertos/*.patch
	-cd $(pwd)/$(linux) &&\
		git checkout v6.1 &&\
		git pull --depth 1 &&\
		git apply $(pwd)/patches/linux/*.patch
	-cd $(pwd)/$(buildroot) &&\
		git checkout 2022.11 &&\
		git pull --depth 1
	-cd $(pwd)/$(uboot) &&\
		git checkout v2022.10 &&\
		git pull --depth 1
	-cd $(pwd)/$(TFA) &&\
		git checkout bao/demo &&\
		git pull --depth 1
	-cd $(pwd)/$(firmware) &&\
		git checkout 1.20210201 &&\
		git pull --depth 1
	-cd $(pwd)/$(bao) &&\
		git checkout demo &&\
		git pull --depth 1

lf: linux wrap_linux freertos
	$(MAKE) OS=lf bao

baremetal: init $(baremetal)/
	$(MAKE) -C $(pwd)/$(baremetal) clean
	$(MAKE) -C $(pwd)/$(baremetal) PLATFORM=$(PLATFORM)
	cp $(pwd)/$(baremetal)/build/$(PLATFORM)/baremetal.bin $(build_dir)/
	$(MAKE) OS=bare bao

qemu: init $(uboot)/ $(TFA)/
	$(MAKE) -C $(pwd)/$(uboot) qemu_arm64_defconfig
	echo "CONFIG_TFABOOT=y" >> $(pwd)/$(uboot)/.config
	echo "CONFIG_SYS_TEXT_BASE=0x60000000" >> $(pwd)/$(uboot)/.config
	$(MAKE) -C $(pwd)/$(uboot) -j$(proc)
	$(MAKE) -C $(pwd)/$(TFA) PLAT=qemu bl1 fip BL33=$(pwd)/$(uboot)/u-boot.bin QEMU_USE_GIC_DRIVER=QEMU_GICV3
	dd if=$(pwd)/$(TFA)/build/qemu/release/bl1.bin of=$(build_dir)/flash.bin
	dd if=$(pwd)/$(TFA)/build/qemu/release/fip.bin of=$(build_dir)/flash.bin seek=64 bs=4096 conv=notrunc

qemu_run:
	qemu-system-aarch64\
	 -nographic\
   -M virt,secure=on,virtualization=on,gic-version=3 \
   -cpu cortex-a53 -smp 4 -m 4G\
   -bios $(build_dir)/flash.bin \
   -device loader,file="$(build_dir)/freertos.bin",addr=0x50000000,force-raw=on\
	 -device virtio-net-device,netdev=net0\
	 -netdev user,id=net0,net=192.168.42.0/24,hostfwd=tcp:127.0.0.1:5555-:22\
	 -device virtio-serial-device -chardev pty,id=serial3 -device virtconsole,chardev=serial3

clean:
	rm -rf $(build_dir)
	$(MAKE) -C $(pwd)/$(freertos) clean
	$(MAKE) -C $(pwd)/$(buildroot) clean
	$(MAKE) -C $(pwd)/$(lloader) clean
	$(MAKE) -C $(pwd)/$(uboot) clean
	$(MAKE) -C $(pwd)/$(TFA) clean
	$(MAKE) -C $(pwd)/$(bao) clean

.PHONY: init patches pack clean qemu
