CFILES = $(wildcard *.c)
OFILES = $(CFILES:.c=.o)
GCCFLAGS = -Wall -O2 -ffreestanding -nostdinc -nostdlib -nostartfiles
TOOLCHAIN ?= aarch64-none-elf-

all: clean kernel8.img

boot.o: boot.S
	$(TOOLCHAIN)gcc $(GCCFLAGS) -c boot.S -o boot.o

%.o: %.c
	$(TOOLCHAIN)gcc $(GCCFLAGS) -c $< -o $@

kernel8.img: boot.o $(OFILES)
	$(TOOLCHAIN)ld -nostdlib boot.o $(OFILES) -T link.ld -o kernel8.elf
	$(TOOLCHAIN)objcopy -O binary kernel8.elf kernel8.img

clean:
	/bin/rm kernel8.elf *.o *.img > /dev/null 2> /dev/null || true
