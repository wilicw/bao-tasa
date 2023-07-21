platform:=rpi4
freertos:=freertos-over-bao

all: freertos

freertos:
	make -C $(freertos) clean
	make -C $(freertos) PLATFORM=$(platform) STD_ADDR_SPACE=y

patches:
	# Patch freertos
	git apply --directory=$(freertos)/src/baremetal-runtime patches/freertos/drivers/*.patch
	git apply --directory=$(freertos) patches/freertos/*.patch

.PHONY: patches
