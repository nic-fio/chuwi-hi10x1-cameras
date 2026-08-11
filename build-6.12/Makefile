# Build fuori albero dei driver camera contro il kernel Debian in esecuzione.
#
#   make            # compila i moduli
#   make clean
#
# I sorgenti .c sono copie non modificate di /home/nicfio/linux: le differenze
# di API fra la 7.2 e la 6.12 stanno tutte in compat-6.12.h, incluso a forza.

KDIR ?= /lib/modules/$(shell uname -r)/build
PWD  := $(shell pwd)

obj-m += gc5035.o gc8034.o ipu-bridge.o

ccflags-y += -include $(src)/compat-6.12.h

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
