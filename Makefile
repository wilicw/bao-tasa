pwd:=$(shell pwd)
platform:=rpi4
ARCH:=aarch64
freertos:=freertos-over-bao
buildroot:=buildroot
proc:=$(shell nproc)
build_dir:=$(pwd)/build
linux:=linux
lloader:=lloader

all: init patches linux wrap_linux freertos

init:
	mkdir -p $(build_dir)

freertos:
	$(MAKE) -C $(pwd)/$(freertos) clean
	$(MAKE) -C $(pwd)/$(freertos) PLATFORM=$(platform) STD_ADDR_SPACE=y -j$(proc)

export LINUX_OVERRIDE_SRCDIR=$(pwd)/$(linux)
export BAO_DEMOS_LINUX_CFG_FRAG=$(pwd)/configs/linux/base.config $(pwd)/configs/linux/$(ARCH).config $(pwd)/configs/linux/$(platform).config
linux:
	# Build buildroot
	$(MAKE) -C $(pwd)/$(buildroot) defconfig BR2_DEFCONFIG=$(pwd)/configs/buildroot/$(ARCH).config -j$(proc)
	# Build Kernel
	-$(MAKE) -C $(pwd)/$(buildroot) linux-reconfigure all
	cp $(pwd)/$(buildroot)/output/images/Image $(build_dir)/

wrap_linux:
	# Compile device tree
	dtc $(pwd)/devicetrees/linux.dts > $(build_dir)/linux.dtb
	# Link
	$(MAKE) -C $(pwd)/$(lloader) ARCH=$(ARCH) IMAGE=$(build_dir)/Image DTB=$(build_dir)/linux.dtb TARGET=$(build_dir)/linux

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

.PHONY: init patches linux freertos wrap_linux
