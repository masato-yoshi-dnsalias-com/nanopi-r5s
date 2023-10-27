all: dtb uboot ubuntu

ubuntu: nanopi-r5s

nanopi-r5s: dtb uboot nanopi-r5s/mmc_4g.img
	@echo "ubuntu nanopi-r5s image make"

dtb: dtb/rk3568-nanopi-r5s.dtb
	@echo "device tree binaries maek"

uboot: uboot/idbloader-r5s.img uboot/u-boot-r5s.itb
	@echo "u-boot binaries make"

clean:
	@rm -fr dtb/linux-* dtb/*.dts dtb/*.dtb 
	@rm -fr uboot/rkbin uboot/u-boot uboot/*.img uboot/*.itb
	@rm -fr nanopi-r5s/cache.* nanopi-r5s/mmc_4g.img*

pkg_install:
	bash pkg_install.sh

nanopi-r5s/mmc_4g.img:
	bash nanopi-r5s/make_image.sh

dtb/rk3568-nanopi-r5s.dtb:
	bash dtb/make_dtb.sh cp

uboot/idbloader-r5s.img uboot/u-boot-r5s.itb:
	bash uboot/make_uboot.sh

.PHONY: ubuntu nanpi-r5s dtb uboot all package-* clean
