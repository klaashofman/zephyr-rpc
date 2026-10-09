if(CONFIG_FRDM_IMX95_DTCM_ECC_INIT)
  zephyr_library()
  zephyr_library_sources(src/dtcm_ecc_init.S)
endif()
