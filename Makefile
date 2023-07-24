pwd:=$(shell pwd)
platform:=rpi4
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

export LINUX_OVERRIDE_SRCDIR=$(pwd)/$(linux)
export BAO_DEMOS_LINUX_CFG_FRAG=$(pwd)/configs/linux/base.config $(pwd)/configs/linux/$(ARCH).config $(pwd)/configs/linux/$(platform).config
export CROSS_COMPILE=aarch64-none-elf-

all: init linux wrap_linux freertos rasp bao pack

init:
	mkdir -p $(build_dir)

freertos: $(freertos)/
	$(MAKE) -C $(pwd)/$(freertos) PLATFORM=$(platform) STD_ADDR_SPACE=y -j$(proc)
	cp $(pwd)/$(freertos)/build/$(platform)/freertos.bin $(build_dir)

linux: $(linux)/ $(buildroot)/
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

rasp: $(TFA)/ $(firmware)/ $(uboot)/
	$(MAKE) -C $(pwd)/$(uboot) rpi_4_defconfig
	$(MAKE) -C $(pwd)/$(uboot) -j$(proc)
	cp $(pwd)/$(uboot)/u-boot.bin $(build_dir)/
	$(MAKE) -C $(pwd)/$(TFA) PLAT=$(platform) -j$(proc)
	cp $(pwd)/$(TFA)/build/$(platform)/release/bl31.bin $(build_dir)

bao: linux freertos
	make -C $(pwd)/$(bao) clean
	make -C $(pwd)/$(bao)\
		PLATFORM=$(platform)\
		CONFIG_REPO=$(pwd)/configs\
		CONFIG=$(platform)\
    CPPFLAGS=-DBAO_DEMOS_WRKDIR_IMGS=$(build_dir)\
		-j$(proc)
	cp $(pwd)/$(bao)/bin/$(platform)/$(platform)/bao.bin $(build_dir)

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

clean:
	rm -rf $(build_dir)
	make -C $(pwd)/$(freertos) clean
	make -C $(pwd)/$(buildroot) clean
	make -C $(pwd)/$(lloader) clean
	make -C $(pwd)/$(uboot) clean
	make -C $(pwd)/$(TFA) clean
	make -C $(pwd)/$(bao) clean

.PHONY: init patches pack clean
