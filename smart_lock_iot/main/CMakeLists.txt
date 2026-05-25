idf_component_register(SRCS "main.cpp"
                       INCLUDE_DIRS "."
                       REQUIRES
                           bt
                           nvs_flash
                           esp_wifi
                           esp_event
                           esp_netif
                           esp_http_client
                           esp_psram
                           esp_driver_gpio
                           esp_driver_i2c
                           espressif__cjson
                           espressif__esp32-camera)
