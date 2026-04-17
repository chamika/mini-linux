.PHONY: all setup bootstrap kernel-config kernel packages configure desktop boot-optimize usb-image install kernel-update clean help

SCRIPTS := scripts

# Configurable variables — override on the command line, e.g.:
#   make configure MINI_LINUX_USER=chamika MINI_LINUX_HOSTNAME=mini
MINI_LINUX_USER     ?= user
MINI_LINUX_HOSTNAME ?= mini-linux
KERNEL_VERSION      ?= 6.12
BUILD_DIR           ?= /var/tmp/mini-linux-build
IMAGE_SIZE          ?= 10G

# Pass these explicitly to sudo so they survive env_reset in sudoers
SUDO_ENV := MINI_LINUX_USER="$(MINI_LINUX_USER)" \
            MINI_LINUX_HOSTNAME="$(MINI_LINUX_HOSTNAME)" \
            KERNEL_VERSION="$(KERNEL_VERSION)" \
            BUILD_DIR="$(BUILD_DIR)" \
            IMAGE_SIZE="$(IMAGE_SIZE)"

setup:
	sudo $(SUDO_ENV) bash $(SCRIPTS)/setup-host.sh

all: bootstrap kernel packages configure desktop boot-optimize usb-image
	@echo ""
	@echo "========================================="
	@echo " Build complete! USB image is ready."
	@echo " Flash with: sudo dd if=build/mini-linux.img of=/dev/sdX bs=4M status=progress"
	@echo "========================================="

bootstrap:
	sudo $(SUDO_ENV) bash $(SCRIPTS)/00-bootstrap.sh

kernel-config:
	sudo $(SUDO_ENV) bash $(SCRIPTS)/01-kernel-config.sh

kernel:
	sudo $(SUDO_ENV) bash $(SCRIPTS)/02-kernel-build.sh

packages:
	sudo $(SUDO_ENV) bash $(SCRIPTS)/03-packages.sh

configure:
	sudo $(SUDO_ENV) bash $(SCRIPTS)/04-configure.sh

desktop:
	sudo $(SUDO_ENV) bash $(SCRIPTS)/05-desktop-setup.sh

boot-optimize:
	sudo $(SUDO_ENV) bash $(SCRIPTS)/06-boot-optimize.sh

usb-image:
	sudo $(SUDO_ENV) bash $(SCRIPTS)/07-build-usb-image.sh

install:
	sudo $(SUDO_ENV) bash $(SCRIPTS)/08-install-to-nvme.sh

kernel-update:
	sudo $(SUDO_ENV) bash $(SCRIPTS)/09-kernel-update.sh

clean:
	@echo "Removing build directory (${BUILD_DIR})..."
	sudo rm -rf "$(BUILD_DIR)"
	@echo "Clean complete."

help:
	@echo "Mini-Linux Build System"
	@echo ""
	@echo "  make setup          - Install build dependencies on Ubuntu (run once)"
	@echo "  make all            - Full build pipeline (bootstrap → USB image)"
	@echo "  make bootstrap      - Create Arch Linux base rootfs"
	@echo "  make kernel-config  - Generate custom kernel config for XPS 13"
	@echo "  make kernel         - Compile and install custom kernel"
	@echo "  make packages       - Install desktop and application packages"
	@echo "  make configure      - Apply system configuration"
	@echo "  make desktop        - Set up GNOME desktop environment"
	@echo "  make boot-optimize  - Apply boot time optimizations"
	@echo "  make usb-image      - Generate bootable USB image"
	@echo "  make install        - Install to NVMe (dual-boot with Ubuntu)"
	@echo "  make kernel-update  - Update kernel on installed NVMe without data loss"
	@echo "  make clean          - Remove build directory"
