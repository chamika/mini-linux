.PHONY: all setup bootstrap kernel-config kernel packages configure desktop boot-optimize usb-image install clean help

SCRIPTS := scripts

setup:
	sudo bash $(SCRIPTS)/setup-host.sh

all: bootstrap kernel packages configure desktop boot-optimize usb-image
	@echo ""
	@echo "========================================="
	@echo " Build complete! USB image is ready."
	@echo " Flash with: sudo dd if=build/mini-linux.img of=/dev/sdX bs=4M status=progress"
	@echo "========================================="

bootstrap:
	sudo bash $(SCRIPTS)/00-bootstrap.sh

kernel-config:
	sudo bash $(SCRIPTS)/01-kernel-config.sh

kernel:
	sudo bash $(SCRIPTS)/02-kernel-build.sh

packages:
	sudo bash $(SCRIPTS)/03-packages.sh

configure:
	sudo bash $(SCRIPTS)/04-configure.sh

desktop:
	sudo bash $(SCRIPTS)/05-hyprland-setup.sh

boot-optimize:
	sudo bash $(SCRIPTS)/06-boot-optimize.sh

usb-image:
	sudo bash $(SCRIPTS)/07-build-usb-image.sh

install:
	sudo bash $(SCRIPTS)/08-install-to-nvme.sh

clean:
	@echo "Removing build directory..."
	sudo rm -rf /tmp/mini-linux-build
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
	@echo "  make desktop        - Set up Hyprland desktop environment"
	@echo "  make boot-optimize  - Apply boot time optimizations"
	@echo "  make usb-image      - Generate bootable USB image"
	@echo "  make install        - Install to NVMe (dual-boot with Ubuntu)"
	@echo "  make clean          - Remove build directory"
