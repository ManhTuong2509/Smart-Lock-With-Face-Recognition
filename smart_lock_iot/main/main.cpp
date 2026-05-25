#include <stdio.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/event_groups.h"
#include "driver/gpio.h"
#include "driver/i2c_master.h"
#include "esp_log.h"
#include "esp_camera.h" 
#include "nvs_flash.h"
#include "nvs.h"
#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_http_client.h"
#include "esp_heap_caps.h"
#include "esp_psram.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "host/ble_hs.h"
#include "host/ble_hs_mbuf.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"
#include "cJSON.h" 
#include "rom/ets_sys.h" 

// ================= CẤU HÌNH WI-FI & SERVER =================
#define ALERT_FAIL_THRESHOLD 4

#define CONFIG_NAMESPACE "smart_lock"
#define MAX_SSID_LEN 32
#define MAX_WIFI_PASS_LEN 64
#define MAX_CLOUD_URL_LEN 160
#define MAX_TEMP_KEY_LEN 32

// ================= CẤU HÌNH PHẦN CỨNG =================
#define VIBRATION_SENSOR_PIN  GPIO_NUM_1
#define LED_GREEN_PIN         GPIO_NUM_42
#define LED_RED_PIN           GPIO_NUM_2
#define BUZZER_PIN            GPIO_NUM_41
#define RELAY_LOCK_PIN        GPIO_NUM_3
#define BOOT_BUTTON_PIN       GPIO_NUM_0 

// ================= CẤU HÌNH I2C CHO LCD1602 =================
#define I2C_MASTER_SCL_IO           GPIO_NUM_14
#define I2C_MASTER_SDA_IO           GPIO_NUM_46
#define LCD_ADDR                    0x27

// ================= CẤU HÌNH KEYPAD 4x3 & MẬT KHẨU =================
#define CORRECT_PASS "1357908642" 

#define ROW_1 GPIO_NUM_21
#define ROW_2 GPIO_NUM_47
#define ROW_3 GPIO_NUM_48
#define ROW_4 GPIO_NUM_45

#define COL_1 GPIO_NUM_38
#define COL_2 GPIO_NUM_39
#define COL_3 GPIO_NUM_40


gpio_num_t row_pins[4] = {ROW_1, ROW_2, ROW_3, ROW_4};
gpio_num_t col_pins[3] = {COL_1, COL_2, COL_3}; 


char keys[4][3] = {
    {'1','2','3'},
    {'4','5','6'},
    {'7','8','9'},
    {'*','0','#'}
};

// ================= CẤU HÌNH CAMERA =================
#define CAM_PIN_PWDN -1
#define CAM_PIN_RESET -1
#define CAM_PIN_XCLK 15
#define CAM_PIN_SIOD 4
#define CAM_PIN_SIOC 5
#define CAM_PIN_Y9 16
#define CAM_PIN_Y8 17
#define CAM_PIN_Y7 18
#define CAM_PIN_Y6 12
#define CAM_PIN_Y5 10
#define CAM_PIN_Y4 8
#define CAM_PIN_Y3 9
#define CAM_PIN_Y2 11
#define CAM_PIN_VSYNC 6
#define CAM_PIN_HREF 7
#define CAM_PIN_PCLK 13

#define CAMERA_XCLK_FREQ_HZ 10000000
#define CAMERA_JPEG_QUALITY 12
#define CAMERA_CAPTURE_RETRIES 3

static const char *TAG = "SMART_LOCK";
static int fail_count = 0;
static EventGroupHandle_t wifi_event_group;
#define WIFI_CONNECTED_BIT BIT0

struct DeviceConfig {
    char wifi_ssid[MAX_SSID_LEN + 1];
    char wifi_pass[MAX_WIFI_PASS_LEN + 1];
    char cloud_url[MAX_CLOUD_URL_LEN + 1];
    char temp_key[MAX_TEMP_KEY_LEN + 1];
};

static DeviceConfig device_config = {};
static bool wifi_ready = false;
static bool camera_ready = false;
static uint8_t ble_own_addr_type;

static bool wait_for_wifi_connected(TickType_t timeout_ticks) {
    if (!wifi_event_group) return false;
    EventBits_t bits = xEventGroupWaitBits(
        wifi_event_group,
        WIFI_CONNECTED_BIT,
        pdFALSE,
        pdTRUE,
        timeout_ticks
    );
    return (bits & WIFI_CONNECTED_BIT) != 0;
}

// BLE UUIDs app can use to provision this board.
// Service:        7b0f0001-64f0-4f5b-9f89-5d9b3f4c2a10
// Config write:   7b0f0002-64f0-4f5b-9f89-5d9b3f4c2a10
static const ble_uuid128_t smart_lock_svc_uuid =
    BLE_UUID128_INIT(0x10, 0x2a, 0x4c, 0x3f, 0x9b, 0x5d, 0x89, 0x9f, 0x5b, 0x4f, 0xf0, 0x64, 0x01, 0x00, 0x0f, 0x7b);
static const ble_uuid128_t smart_lock_cfg_chr_uuid =
    BLE_UUID128_INIT(0x10, 0x2a, 0x4c, 0x3f, 0x9b, 0x5d, 0x89, 0x9f, 0x5b, 0x4f, 0xf0, 0x64, 0x02, 0x00, 0x0f, 0x7b);

static void copy_json_string(cJSON *root, const char *name, char *dest, size_t dest_size) {
    cJSON *item = cJSON_GetObjectItem(root, name);
    if (item && cJSON_IsString(item) && item->valuestring) {
        strlcpy(dest, item->valuestring, dest_size);
    }
}

static void trim_trailing_slashes(char *value) {
    size_t len = strlen(value);
    while (len > 0 && value[len - 1] == '/') {
        value[len - 1] = '\0';
        len--;
    }
}

static bool has_url_scheme(const char *value) {
    return strncmp(value, "http://", 7) == 0 || strncmp(value, "https://", 8) == 0;
}

static void normalize_cloud_base_url() {
    char normalized[MAX_CLOUD_URL_LEN + 1] = {};
    if (has_url_scheme(device_config.cloud_url)) {
        strlcpy(normalized, device_config.cloud_url, sizeof(normalized));
    } else {
        strlcpy(normalized, "http://", sizeof(normalized));
        strlcat(normalized, device_config.cloud_url, sizeof(normalized));
    }
    strlcpy(device_config.cloud_url, normalized, sizeof(device_config.cloud_url));
    trim_trailing_slashes(device_config.cloud_url);
}

static void build_cloud_url(char *out, size_t out_size, const char *path) {
    normalize_cloud_base_url();
    snprintf(out, out_size, "%s%s", device_config.cloud_url, path);
}

static esp_err_t nvs_get_string_or_default(nvs_handle_t nvs, const char *key, char *out, size_t out_size, const char *fallback) {
    size_t required_size = out_size;
    esp_err_t err = nvs_get_str(nvs, key, out, &required_size);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        strlcpy(out, fallback, out_size);
        return ESP_OK;
    }
    if (err != ESP_OK) {
        strlcpy(out, fallback, out_size);
        return err;
    }
    out[out_size - 1] = '\0';
    return ESP_OK;
}

static void load_device_config() {
    nvs_handle_t nvs;
    esp_err_t err = nvs_open(CONFIG_NAMESPACE, NVS_READONLY, &nvs);
    if (err != ESP_OK) {
        strlcpy(device_config.wifi_ssid, DEFAULT_WIFI_SSID, sizeof(device_config.wifi_ssid));
        strlcpy(device_config.wifi_pass, DEFAULT_WIFI_PASS, sizeof(device_config.wifi_pass));
        strlcpy(device_config.cloud_url, DEFAULT_CLOUD_URL, sizeof(device_config.cloud_url));
        device_config.temp_key[0] = '\0';
        return;
    }

    nvs_get_string_or_default(nvs, "ssid", device_config.wifi_ssid, sizeof(device_config.wifi_ssid), DEFAULT_WIFI_SSID);
    nvs_get_string_or_default(nvs, "wifi_pass", device_config.wifi_pass, sizeof(device_config.wifi_pass), DEFAULT_WIFI_PASS);
    nvs_get_string_or_default(nvs, "cloud_url", device_config.cloud_url, sizeof(device_config.cloud_url), DEFAULT_CLOUD_URL);
    nvs_get_string_or_default(nvs, "temp_key", device_config.temp_key, sizeof(device_config.temp_key), "");
    normalize_cloud_base_url();
    nvs_close(nvs);
}

static esp_err_t save_device_config() {
    nvs_handle_t nvs;
    esp_err_t err = nvs_open(CONFIG_NAMESPACE, NVS_READWRITE, &nvs);
    if (err != ESP_OK) return err;

    normalize_cloud_base_url();
    err = nvs_set_str(nvs, "ssid", device_config.wifi_ssid);
    if (err == ESP_OK) err = nvs_set_str(nvs, "wifi_pass", device_config.wifi_pass);
    if (err == ESP_OK) err = nvs_set_str(nvs, "cloud_url", device_config.cloud_url);
    if (err == ESP_OK) err = nvs_set_str(nvs, "temp_key", device_config.temp_key);
    if (err != ESP_OK) {
        nvs_close(nvs);
        return err;
    }
    err = nvs_commit(nvs);
    nvs_close(nvs);
    return err;
}

static void clear_temp_key() {
    device_config.temp_key[0] = '\0';
    nvs_handle_t nvs;
    if (nvs_open(CONFIG_NAMESPACE, NVS_READWRITE, &nvs) == ESP_OK) {
        nvs_set_str(nvs, "temp_key", "");
        nvs_commit(nvs);
        nvs_close(nvs);
    }
}

void process_correct_access(const char* user_name);

// ================== HÀM ĐIỀU KHIỂN KEYPAD ==================
void init_keypad() {
    // Khởi tạo 4 chân Hàng
    for (int i = 0; i < 4; i++) {
        gpio_reset_pin(row_pins[i]);
        gpio_set_direction(row_pins[i], GPIO_MODE_OUTPUT);
        gpio_set_level(row_pins[i], 1); 
    }
    // Khởi tạo 3 chân Cột
    for (int i = 0; i < 3; i++) { 
        gpio_reset_pin(col_pins[i]);
        gpio_set_direction(col_pins[i], GPIO_MODE_INPUT);
        gpio_set_pull_mode(col_pins[i], GPIO_PULLUP_ONLY); 
    }
}

char read_keypad() {
    for (int r = 0; r < 4; r++) {
        gpio_set_level(row_pins[r], 0); 
        for (int c = 0; c < 3; c++) { // Vòng lặp quét 3 cột
            if (gpio_get_level(col_pins[c]) == 0) { 
                vTaskDelay(pdMS_TO_TICKS(20)); 
                if (gpio_get_level(col_pins[c]) == 0) { 
                    while(gpio_get_level(col_pins[c]) == 0) {
                        vTaskDelay(pdMS_TO_TICKS(10)); 
                    }
                    gpio_set_level(row_pins[r], 1); 
                    return keys[r][c]; 
                }
            }
        }
        gpio_set_level(row_pins[r], 1); 
    }
    return '\0'; 
}
// ================== HÀM ĐIỀU KHIỂN LCD I2C ==================
i2c_master_dev_handle_t lcd_handle;

void lcd_send_nibble(char nibble) {
    char data_u = (nibble & 0xf0);
    uint8_t data_t[2] = { (uint8_t)(data_u | 0x0C), (uint8_t)(data_u | 0x08) };
    i2c_master_transmit(lcd_handle, data_t, 2, -1);
    ets_delay_us(100);
}

void lcd_send_cmd(char cmd) {
    char data_u = (cmd & 0xf0); char data_l = ((cmd << 4) & 0xf0);
    uint8_t data_t[4] = { (uint8_t)(data_u | 0x0C), (uint8_t)(data_u | 0x08), (uint8_t)(data_l | 0x0C), (uint8_t)(data_l | 0x08) };
    i2c_master_transmit(lcd_handle, data_t, 4, -1);
    ets_delay_us(100);
}

void lcd_send_data(char data) {
    char data_u = (data & 0xf0); char data_l = ((data << 4) & 0xf0);
    uint8_t data_t[4] = { (uint8_t)(data_u | 0x0D), (uint8_t)(data_u | 0x09), (uint8_t)(data_l | 0x0D), (uint8_t)(data_l | 0x09) };
    i2c_master_transmit(lcd_handle, data_t, 4, -1);
    ets_delay_us(100);
}

void lcd_init(void) {
    i2c_master_bus_config_t i2c_bus_config = {};
    i2c_bus_config.clk_source = I2C_CLK_SRC_DEFAULT;
    i2c_bus_config.i2c_port = -1;
    i2c_bus_config.scl_io_num = (gpio_num_t)I2C_MASTER_SCL_IO;
    i2c_bus_config.sda_io_num = (gpio_num_t)I2C_MASTER_SDA_IO;
    i2c_bus_config.glitch_ignore_cnt = 7;
    i2c_bus_config.flags.enable_internal_pullup = true;

    i2c_master_bus_handle_t bus_handle;
    ESP_ERROR_CHECK(i2c_new_master_bus(&i2c_bus_config, &bus_handle));

    i2c_device_config_t dev_cfg = {};
    dev_cfg.dev_addr_length = I2C_ADDR_BIT_LEN_7;
    dev_cfg.device_address = LCD_ADDR;
    dev_cfg.scl_speed_hz = 100000;

    ESP_ERROR_CHECK(i2c_master_bus_add_device(bus_handle, &dev_cfg, &lcd_handle));

    ets_delay_us(50000); 
    lcd_send_nibble(0x30); ets_delay_us(5000); 
    lcd_send_nibble(0x30); ets_delay_us(200);  
    lcd_send_nibble(0x30); ets_delay_us(200);  
    lcd_send_nibble(0x20); ets_delay_us(200);  
    
    lcd_send_cmd(0x28); ets_delay_us(100); 
    lcd_send_cmd(0x08); ets_delay_us(100); 
    lcd_send_cmd(0x01); ets_delay_us(5000); 
    lcd_send_cmd(0x06); ets_delay_us(100); 
    lcd_send_cmd(0x0C); ets_delay_us(100); 
}

void lcd_clear() { 
    lcd_send_cmd(0x01); 
    ets_delay_us(5000); 
}

void lcd_put_cur(int row, int col) { lcd_send_cmd(row == 0 ? (col | 0x80) : (col | 0xC0)); }
void lcd_send_string(const char *str) { while (*str) lcd_send_data(*str++); }

// ================== HÀM KHỞI TẠO HỆ THỐNG ==================
static void wifi_event_handler(void* arg, esp_event_base_t event_base, int32_t event_id, void* event_data) {
    if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_START) {
        if (device_config.wifi_ssid[0] != '\0') esp_wifi_connect();
    }
    else if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_DISCONNECTED) {
        wifi_event_sta_disconnected_t *disconnected = (wifi_event_sta_disconnected_t *)event_data;
        xEventGroupClearBits(wifi_event_group, WIFI_CONNECTED_BIT);
        ESP_LOGW(TAG, "WiFi disconnected, reason=%d", disconnected ? disconnected->reason : -1);
        if (device_config.wifi_ssid[0] != '\0') esp_wifi_connect();
    } else if (event_base == IP_EVENT && event_id == IP_EVENT_STA_GOT_IP) {
        xEventGroupSetBits(wifi_event_group, WIFI_CONNECTED_BIT);
        ESP_LOGI(TAG, "WiFi Connected!"); 
        lcd_clear(); lcd_put_cur(0, 0); lcd_send_string("WiFi Connected!");
    }
}

static void connect_wifi_from_config() {
    if (!wifi_ready || device_config.wifi_ssid[0] == '\0') return;

    wifi_config_t wifi_config = {};
    strlcpy((char*)wifi_config.sta.ssid, device_config.wifi_ssid, sizeof(wifi_config.sta.ssid));
    strlcpy((char*)wifi_config.sta.password, device_config.wifi_pass, sizeof(wifi_config.sta.password));
    esp_wifi_disconnect();
    esp_wifi_set_config(WIFI_IF_STA, &wifi_config);
    esp_wifi_connect();
}

void init_wifi() {
    wifi_event_group = xEventGroupCreate();
    esp_netif_init();
    esp_event_loop_create_default();
    esp_netif_create_default_wifi_sta();

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    esp_wifi_init(&cfg);
    esp_event_handler_instance_register(WIFI_EVENT, ESP_EVENT_ANY_ID, &wifi_event_handler, NULL, NULL);
    esp_event_handler_instance_register(IP_EVENT, IP_EVENT_STA_GOT_IP, &wifi_event_handler, NULL, NULL);
    esp_wifi_set_mode(WIFI_MODE_STA);
    wifi_ready = true;
    esp_wifi_start();
    connect_wifi_from_config();
}

static esp_err_t apply_config_json(const char *json) {
    cJSON *root = cJSON_Parse(json);
    if (!root) return ESP_ERR_INVALID_ARG;

    cJSON *command = cJSON_GetObjectItem(root, "command");
    if (command && cJSON_IsString(command) && command->valuestring &&
        strcmp(command->valuestring, "unlock") == 0) {
        cJSON_Delete(root);
        process_correct_access("App");
        return ESP_OK;
    }

    copy_json_string(root, "ssid", device_config.wifi_ssid, sizeof(device_config.wifi_ssid));
    copy_json_string(root, "wifiSsid", device_config.wifi_ssid, sizeof(device_config.wifi_ssid));
    copy_json_string(root, "wifiPassword", device_config.wifi_pass, sizeof(device_config.wifi_pass));
    copy_json_string(root, "password", device_config.wifi_pass, sizeof(device_config.wifi_pass));
    copy_json_string(root, "cloudUrl", device_config.cloud_url, sizeof(device_config.cloud_url));
    copy_json_string(root, "cloudAddress", device_config.cloud_url, sizeof(device_config.cloud_url));
    copy_json_string(root, "cloudLink", device_config.cloud_url, sizeof(device_config.cloud_url));
    copy_json_string(root, "serverUrl", device_config.cloud_url, sizeof(device_config.cloud_url));
    copy_json_string(root, "server", device_config.cloud_url, sizeof(device_config.cloud_url));
    copy_json_string(root, "baseUrl", device_config.cloud_url, sizeof(device_config.cloud_url));
    copy_json_string(root, "cloud", device_config.cloud_url, sizeof(device_config.cloud_url));
    copy_json_string(root, "temporaryKey", device_config.temp_key, sizeof(device_config.temp_key));
    copy_json_string(root, "tempKey", device_config.temp_key, sizeof(device_config.temp_key));
    cJSON_Delete(root);

    esp_err_t err = save_device_config();
    if (err == ESP_OK) {
        ESP_LOGI(TAG, "Received BLE config. SSID=%s, Cloud=%s, TempKey=%s",
                 device_config.wifi_ssid,
                 device_config.cloud_url,
                 device_config.temp_key[0] ? "set" : "empty");
        lcd_clear();
        lcd_put_cur(0, 0); lcd_send_string("BLE config OK");
        lcd_put_cur(1, 0); lcd_send_string("Dang ket noi...");
        connect_wifi_from_config();
    }
    return err;
}

static int ble_config_access_cb(uint16_t conn_handle, uint16_t attr_handle,
                                struct ble_gatt_access_ctxt *ctxt, void *arg) {
    if (ctxt->op != BLE_GATT_ACCESS_OP_WRITE_CHR) return BLE_ATT_ERR_UNLIKELY;

    char json_buffer[384] = {};
    uint16_t out_len = 0;
    int rc = ble_hs_mbuf_to_flat(ctxt->om, json_buffer, sizeof(json_buffer) - 1, &out_len);
    if (rc != 0) return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;

    json_buffer[out_len] = '\0';
    esp_err_t err = apply_config_json(json_buffer);
    return err == ESP_OK ? 0 : BLE_ATT_ERR_UNLIKELY;
}

static const struct ble_gatt_chr_def smart_lock_gatt_chrs[] = {
    {
        .uuid = &smart_lock_cfg_chr_uuid.u,
        .access_cb = ble_config_access_cb,
        .arg = NULL,
        .descriptors = NULL,
        .flags = BLE_GATT_CHR_F_WRITE | BLE_GATT_CHR_F_WRITE_NO_RSP,
        .min_key_size = 0,
        .val_handle = NULL,
        .cpfd = NULL,
    },
    { NULL, NULL, NULL, NULL, 0, 0, NULL, NULL },
};

static const struct ble_gatt_svc_def smart_lock_gatt_svcs[] = {
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = &smart_lock_svc_uuid.u,
        .includes = NULL,
        .characteristics = smart_lock_gatt_chrs,
    },
    { 0, NULL, NULL, NULL },
};

static void ble_start_advertising();

static int ble_gap_event_cb(struct ble_gap_event *event, void *arg) {
    if (event->type == BLE_GAP_EVENT_DISCONNECT || event->type == BLE_GAP_EVENT_ADV_COMPLETE) {
        ble_start_advertising();
    }
    return 0;
}

static void ble_start_advertising() {
    struct ble_gap_adv_params adv_params = {};
    adv_params.conn_mode = BLE_GAP_CONN_MODE_UND;
    adv_params.disc_mode = BLE_GAP_DISC_MODE_GEN;

    struct ble_hs_adv_fields fields = {};
    const char *device_name = ble_svc_gap_device_name();
    fields.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    fields.name = (uint8_t *)device_name;
    fields.name_len = strlen(device_name);
    fields.name_is_complete = 1;
    int rc = ble_gap_adv_set_fields(&fields);
    if (rc != 0) {
        ESP_LOGE(TAG, "BLE advertising fields failed: %d", rc);
        return;
    }

    struct ble_hs_adv_fields rsp_fields = {};
    rsp_fields.uuids128 = &smart_lock_svc_uuid;
    rsp_fields.num_uuids128 = 1;
    rsp_fields.uuids128_is_complete = 1;
    rc = ble_gap_adv_rsp_set_fields(&rsp_fields);
    if (rc != 0) {
        ESP_LOGE(TAG, "BLE scan response fields failed: %d", rc);
        return;
    }

    rc = ble_gap_adv_start(ble_own_addr_type, NULL, BLE_HS_FOREVER, &adv_params, ble_gap_event_cb, NULL);
    if (rc != 0) {
        ESP_LOGE(TAG, "BLE advertising failed: %d", rc);
    } else {
        ESP_LOGI(TAG, "BLE advertising started");
    }
}

static void ble_on_sync() {
    int rc = ble_hs_id_infer_auto(0, &ble_own_addr_type);
    if (rc != 0) {
        ESP_LOGE(TAG, "BLE address infer failed: %d", rc);
        return;
    }
    ble_start_advertising();
}

static void ble_on_reset(int reason) {
    ESP_LOGE(TAG, "BLE reset, reason=%d", reason);
}

static void ble_host_task(void *param) {
    nimble_port_run();
    nimble_port_freertos_deinit();
}

static void init_ble_provisioning() {
    esp_err_t ret = nimble_port_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to init NimBLE: %s", esp_err_to_name(ret));
        return;
    }

    ble_svc_gap_init();
    ble_svc_gatt_init();
    ble_svc_gap_device_name_set("SmartLock-ESP32");

    ble_hs_cfg.reset_cb = ble_on_reset;
    ble_hs_cfg.sync_cb = ble_on_sync;

    int rc = ble_gatts_count_cfg(smart_lock_gatt_svcs);
    if (rc == 0) rc = ble_gatts_add_svcs(smart_lock_gatt_svcs);
    if (rc != 0) {
        ESP_LOGE(TAG, "Failed to add BLE GATT service: %d", rc);
        return;
    }

    nimble_port_freertos_init(ble_host_task);
}

esp_err_t init_camera() {
    esp_camera_set_psram_mode(false);

    camera_config_t config = {};
    config.ledc_channel = LEDC_CHANNEL_0; config.ledc_timer = LEDC_TIMER_0;
    config.pin_d0 = CAM_PIN_Y2; config.pin_d1 = CAM_PIN_Y3; config.pin_d2 = CAM_PIN_Y4;
    config.pin_d3 = CAM_PIN_Y5; config.pin_d4 = CAM_PIN_Y6; config.pin_d5 = CAM_PIN_Y7;
    config.pin_d6 = CAM_PIN_Y8; config.pin_d7 = CAM_PIN_Y9;
    config.pin_xclk = CAM_PIN_XCLK; config.pin_pclk = CAM_PIN_PCLK;
    config.pin_vsync = CAM_PIN_VSYNC; config.pin_href = CAM_PIN_HREF;
    config.pin_sccb_sda = CAM_PIN_SIOD; config.pin_sccb_scl = CAM_PIN_SIOC;
    config.pin_pwdn = CAM_PIN_PWDN; config.pin_reset = CAM_PIN_RESET;
    bool psram_ready = esp_psram_is_initialized();
    ESP_LOGI(TAG, "PSRAM %s, free PSRAM=%u bytes",
             psram_ready ? "ready" : "not ready",
             (unsigned)heap_caps_get_free_size(MALLOC_CAP_SPIRAM));

    config.xclk_freq_hz = CAMERA_XCLK_FREQ_HZ; config.pixel_format = PIXFORMAT_JPEG;
    config.frame_size = FRAMESIZE_QVGA; config.jpeg_quality = CAMERA_JPEG_QUALITY;
    config.fb_count = 1; config.grab_mode = CAMERA_GRAB_WHEN_EMPTY;
    config.fb_location = psram_ready ? CAMERA_FB_IN_PSRAM : CAMERA_FB_IN_DRAM; 
    config.sccb_i2c_port = -1;
    esp_err_t err = esp_camera_init(&config);
    if (err == ESP_OK) {
        camera_ready = true;
        sensor_t * s = esp_camera_sensor_get();
        s->set_vflip(s, 1);
        ESP_LOGI(TAG, "Camera ready, PSRAM DMA=%s",
                 esp_camera_get_psram_mode() ? "on" : "off");
    } else {
        camera_ready = false;
        ESP_LOGE(TAG, "Camera init failed: %s", esp_err_to_name(err));
    }
    return err;
}

void init_hardware() {
    gpio_reset_pin(VIBRATION_SENSOR_PIN); gpio_set_direction(VIBRATION_SENSOR_PIN, GPIO_MODE_INPUT); gpio_set_pull_mode(VIBRATION_SENSOR_PIN, GPIO_PULLDOWN_ONLY);
    gpio_reset_pin(BOOT_BUTTON_PIN); gpio_set_direction(BOOT_BUTTON_PIN, GPIO_MODE_INPUT); gpio_set_pull_mode(BOOT_BUTTON_PIN, GPIO_PULLUP_ONLY); 
    gpio_reset_pin(LED_GREEN_PIN); gpio_set_direction(LED_GREEN_PIN, GPIO_MODE_OUTPUT);
    gpio_reset_pin(LED_RED_PIN); gpio_set_direction(LED_RED_PIN, GPIO_MODE_OUTPUT);
    gpio_reset_pin(BUZZER_PIN); gpio_set_direction(BUZZER_PIN, GPIO_MODE_OUTPUT);
    gpio_reset_pin(RELAY_LOCK_PIN); gpio_set_direction(RELAY_LOCK_PIN, GPIO_MODE_OUTPUT);

    
    gpio_set_level(RELAY_LOCK_PIN, 1); 
    init_keypad(); // Khởi tạo Keypad
}

// ================== LOGIC ĐÓNG / MỞ CỬA ==================
bool process_wrong_access() {
    fail_count++;
    ESP_LOGW(TAG, "Sai xac thuc! Fail count: %d", fail_count); 
    
    lcd_clear();
    lcd_put_cur(0, 0); lcd_send_string("Tu choi mo cua!");
    
    char fail_str[16];
    sprintf(fail_str, "Fail count: %d", fail_count);
    lcd_put_cur(1, 0); lcd_send_string(fail_str);

    bool should_send_alert = fail_count >= ALERT_FAIL_THRESHOLD;
    if (!should_send_alert) {
        gpio_set_level(LED_RED_PIN, 1); vTaskDelay(pdMS_TO_TICKS(1000)); gpio_set_level(LED_RED_PIN, 0);
    } else {
        ESP_LOGE(TAG, "CANH BAO! Sai qua %d lan", ALERT_FAIL_THRESHOLD);
        lcd_clear(); lcd_put_cur(0, 0); lcd_send_string("CANH BAO!");
        lcd_put_cur(1, 0); lcd_send_string("Sai qua 4 lan");
        gpio_set_level(LED_RED_PIN, 1); gpio_set_level(BUZZER_PIN, 1);
        vTaskDelay(pdMS_TO_TICKS(5000));
        gpio_set_level(LED_RED_PIN, 0); gpio_set_level(BUZZER_PIN, 0);
        fail_count = 0; 
    }
    
    ESP_LOGI(TAG, "San sang...");
    lcd_clear(); lcd_put_cur(0, 0); lcd_send_string("San sang...");
    return should_send_alert;
}

void process_correct_access(const char* user_name) {
    fail_count = 0; 
    ESP_LOGI(TAG, "Welcome Home, %s", user_name); 
    
    lcd_clear();
    lcd_put_cur(0, 0); lcd_send_string("Welcome Home,");
    lcd_put_cur(1, 0); lcd_send_string(user_name);

    gpio_set_level(BUZZER_PIN, 0); gpio_set_level(LED_RED_PIN, 0);
    gpio_set_level(LED_GREEN_PIN, 1); 
    gpio_set_level(RELAY_LOCK_PIN, 0); 
    
    vTaskDelay(pdMS_TO_TICKS(5000)); 
    
    gpio_set_level(LED_GREEN_PIN, 0); 
    gpio_set_level(RELAY_LOCK_PIN, 1);
    
    ESP_LOGI(TAG, "San sang..."); 
    lcd_clear(); lcd_put_cur(0, 0); lcd_send_string("San sang...");
}

// ================== XỬ LÝ GIAO TIẾP SERVER (CAMERA) ==================
static char http_response_buffer[1024];
static int http_response_len = 0;

static void reset_camera_after_capture_error(const char *context) {
    ESP_LOGW(TAG, "%s that bai, reset camera...", context);
    if (camera_ready) {
        esp_camera_deinit();
        camera_ready = false;
    }

    vTaskDelay(pdMS_TO_TICKS(700));
    esp_err_t err = init_camera();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Reset camera that bai: %s", esp_err_to_name(err));
    }
    vTaskDelay(pdMS_TO_TICKS(500));
}

// 1. Sửa lại hàm kiểm tra JPEG: Bỏ kiểm tra byte cuối vì ESP32 thường thêm padding (0x00) ở đuôi file.
static bool is_valid_jpeg(const camera_fb_t *pic) {
    if (!pic || pic->format != PIXFORMAT_JPEG || pic->len < 4) {
        return false;
    }
    // Chỉ cần kiểm tra Header của file JPEG (0xFF 0xD8) là đủ an toàn
    if (pic->buf[0] != 0xFF || pic->buf[1] != 0xD8) {
        return false;
    }
    return true;
}

// 2. Khôi phục và làm cho hàm chụp ảnh ổn định hơn
static camera_fb_t *capture_camera_frame(const char *context) {
    camera_fb_t *pic = NULL;

    if (!camera_ready) {
        ESP_LOGW(TAG, "Camera chua san sang, khoi tao lai...");
        if (init_camera() != ESP_OK) {
            return NULL;
        }
    }
    
    for (int attempt = 1; attempt <= CAMERA_CAPTURE_RETRIES; attempt++) {
        pic = esp_camera_fb_get();
        
        if (is_valid_jpeg(pic)) {
            ESP_LOGI(TAG, "%s OK: %ux%u, %u bytes",
                     context,
                     (unsigned)pic->width,
                     (unsigned)pic->height,
                     (unsigned)pic->len);
            return pic; // Chụp thành công
        }

        if (pic) {
            ESP_LOGW(TAG, "%s loi JPEG lan %d/%d: len=%u, format=%d",
                     context, attempt, CAMERA_CAPTURE_RETRIES,
                     (unsigned)pic->len, pic->format);
            esp_camera_fb_return(pic); // Phải trả lại buffer bị lỗi trước khi thử lại
        } else {
            ESP_LOGW(TAG, "%s khong lay duoc frame lan %d/%d",
                     context, attempt, CAMERA_CAPTURE_RETRIES);
        }

        vTaskDelay(pdMS_TO_TICKS(300)); // Đợi một chút để cảm biến ảnh ổn định lại
    }

    reset_camera_after_capture_error(context);
    return NULL; // Thất bại sau nhiều lần thử
}

// 3. Xử lý HTTP Event (Giữ nguyên, không có lỗi)
esp_err_t _http_event_handler(esp_http_client_event_t *evt) {
    switch(evt->event_id) {
        case HTTP_EVENT_ON_DATA:
            if (evt->data_len > 0) {
                int copy_len = evt->data_len;
                if (http_response_len + copy_len >= sizeof(http_response_buffer)) 
                    copy_len = sizeof(http_response_buffer) - http_response_len - 1;
                memcpy(http_response_buffer + http_response_len, evt->data, copy_len);
                http_response_len += copy_len;
            }
            break;
        case HTTP_EVENT_ON_FINISH:
            http_response_buffer[http_response_len] = '\0';
            break;
        default: break;
    }
    return ESP_OK;
}

// 4. Hàm POST ảnh lên server
static esp_err_t post_jpeg_to_cloud(const char *path, camera_fb_t *pic) {
    if (!wait_for_wifi_connected(pdMS_TO_TICKS(8000))) {
        ESP_LOGE(TAG, "Chua co WiFi, bo qua gui cloud");
        lcd_clear(); lcd_put_cur(0, 0); lcd_send_string("Chua co WiFi!");
        vTaskDelay(pdMS_TO_TICKS(1500));
        return ESP_ERR_WIFI_NOT_CONNECT;
    }

    memset(http_response_buffer, 0, sizeof(http_response_buffer));
    http_response_len = 0;

    char request_url[256] = {};
    build_cloud_url(request_url, sizeof(request_url), path);

    esp_http_client_config_t config = {};
    config.url = request_url;
    config.timeout_ms = 15000; // Tăng timeout lên 15s để tránh rớt mạng giữa chừng khi upload file lớn
    config.event_handler = _http_event_handler;
    // Bỏ qua xác minh chứng chỉ nếu bạn dùng HTTP thường, hoặc server HTTPS tự ký
    config.cert_pem = NULL; 

    esp_http_client_handle_t client = esp_http_client_init(&config);
    if (!client) {
        ESP_LOGE(TAG, "Khong khoi tao duoc HTTP client");
        return ESP_FAIL;
    }

    esp_http_client_set_method(client, HTTP_METHOD_POST);
    esp_http_client_set_header(client, "Content-Type", "image/jpeg");
    esp_http_client_set_post_field(client, (const char*)pic->buf, pic->len);

    ESP_LOGI(TAG, "Dang POST %d bytes len %s", pic->len, request_url);
    
    esp_err_t err = esp_http_client_perform(client);
    if (err == ESP_OK) {
        ESP_LOGI(TAG, "HTTP status=%d, response=%s",
                 esp_http_client_get_status_code(client),
                 http_response_buffer);
    } else {
        ESP_LOGE(TAG, "HTTP loi upload: %s", esp_err_to_name(err));
    }

    esp_http_client_cleanup(client);
    return err;
}

static void send_alert_jpeg(camera_fb_t *pic, const char *source) {
    ESP_LOGW(TAG, "Gui anh canh bao len cloud: %s", source);
    lcd_clear(); lcd_put_cur(0, 0); lcd_send_string("Gui canh bao...");

    esp_err_t err = post_jpeg_to_cloud("/face/unknown-jpg", pic);
    if (err == ESP_OK) {
        ESP_LOGI(TAG, "Cloud da nhan anh canh bao");
        lcd_clear(); lcd_put_cur(0, 0); lcd_send_string("Da gui canh bao");
    } else {
        lcd_clear(); lcd_put_cur(0, 0); lcd_send_string("Loi gui canh bao");
    }
    vTaskDelay(pdMS_TO_TICKS(1500));
}

static void capture_and_send_alert(const char *source) {
    ESP_LOGI(TAG, "Chup anh canh bao...");
    lcd_clear(); lcd_put_cur(0, 0); lcd_send_string("Chup canh bao...");

    camera_fb_t *pic = capture_camera_frame("Chup canh bao");
    if (!pic) {
        ESP_LOGE(TAG, "Loi Camera khi chup canh bao!");
        lcd_put_cur(1, 0); lcd_send_string("Loi Camera!");
        return;
    }

    send_alert_jpeg(pic, source);
    esp_camera_fb_return(pic);
}

void capture_and_send_to_cloud(bool is_enrolling) {
    ESP_LOGI(TAG, "Dang chup anh..."); 
    lcd_clear(); lcd_put_cur(0, 0); lcd_send_string("Dang chup anh...");

    camera_fb_t * pic = capture_camera_frame("Chup AI");
    if (!pic) { 
        ESP_LOGE(TAG, "Loi Camera!"); 
        lcd_put_cur(1, 0); lcd_send_string("Loi Camera!"); 
        return; 
    }

    ESP_LOGI(TAG, "Dang gui AI...");
    lcd_clear(); lcd_put_cur(0, 0); lcd_send_string("Dang gui AI...");
    char path[128] = {};
    if (is_enrolling) {
        snprintf(path, sizeof(path), "/face/register-jpg?user_name=NewUser");
    } else {
        snprintf(path, sizeof(path), "/face/recognize-jpg");
    }

    esp_err_t err = post_jpeg_to_cloud(path, pic);
    
    if (err == ESP_OK && http_response_len > 0) {
        cJSON *root = cJSON_Parse(http_response_buffer);
        if (root != NULL) {
            if (is_enrolling) {
                cJSON *success = cJSON_GetObjectItem(root, "success");
                if (success && cJSON_IsTrue(success)) {
                    lcd_clear(); lcd_put_cur(0, 0); lcd_send_string("Dang ky OK!");
                    gpio_set_level(BUZZER_PIN, 1); vTaskDelay(pdMS_TO_TICKS(200)); gpio_set_level(BUZZER_PIN, 0);
                } else {
                    lcd_clear(); lcd_put_cur(0, 0); lcd_send_string("Dang ky Loi!");
                }
            } else {
                cJSON *found = cJSON_GetObjectItem(root, "found");
                if (found && cJSON_IsTrue(found)) {
                    char u_name[32] = "User";
                    cJSON *meta = cJSON_GetObjectItem(root, "metadata");
                    if (meta) {
                        cJSON *name = cJSON_GetObjectItem(meta, "user_name");
                        if (name && name->valuestring) strncpy(u_name, name->valuestring, sizeof(u_name) - 1);
                    }
                    process_correct_access(u_name); 
                } else {
                    if (process_wrong_access()) {
                        send_alert_jpeg(pic, "face_failed_4_times");
                    }
                }
            }
            cJSON_Delete(root); 
        }
    } else {
        lcd_clear(); lcd_put_cur(0, 0); lcd_send_string("Loi Mang/Server!");
        vTaskDelay(pdMS_TO_TICKS(2000));
        lcd_clear(); lcd_put_cur(0, 0); lcd_send_string("San sang...");
    }

    esp_camera_fb_return(pic);
}

// ================== CHƯƠNG TRÌNH CHÍNH ==================
extern "C" void app_main(void) {
    esp_err_t nvs_ret = nvs_flash_init();
    if (nvs_ret == ESP_ERR_NVS_NO_FREE_PAGES || nvs_ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        nvs_flash_erase();
        nvs_ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(nvs_ret);
    load_device_config();

    init_hardware();
    lcd_init(); 
    
    lcd_clear(); lcd_put_cur(0, 0); lcd_send_string("Khoi dong...");

    if(init_camera() != ESP_OK) {
        lcd_put_cur(1, 0); lcd_send_string("Loi Camera!");
        return; 
    }
    
    init_wifi();
    init_ble_provisioning();
    
    // Biến lưu trữ mật khẩu nhập từ Keypad
    char entered_pass[16] = "";
    int pass_len = 0;

    while (1) {
        // 1. Kiểm tra sự kiện bấm nút Boot (Đăng ký khuôn mặt)
        if (gpio_get_level(BOOT_BUTTON_PIN) == 0) {
            capture_and_send_to_cloud(true); 
            vTaskDelay(pdMS_TO_TICKS(2000)); 
        }
        
        // 2. Kiểm tra cảm biến rung (Nhận diện khuôn mặt)
        if (pass_len == 0 && gpio_get_level(VIBRATION_SENSOR_PIN) == 1) {
            capture_and_send_to_cloud(false); 
            vTaskDelay(pdMS_TO_TICKS(2000)); 
        }
        
        // 3. Kiểm tra Keypad
        char key = read_keypad();
        if (key != '\0') {
            // Có phím bấm -> kêu bíp 1 cái để phản hồi
            gpio_set_level(BUZZER_PIN, 1); 
            vTaskDelay(pdMS_TO_TICKS(50)); 
            gpio_set_level(BUZZER_PIN, 0);

            if (key == '*') {
                // Phím * dùng để xóa bỏ mật khẩu đang gõ dở
                memset(entered_pass, 0, sizeof(entered_pass));
                pass_len = 0;
                lcd_clear(); lcd_put_cur(0, 0); lcd_send_string("San sang...");
            } 
            else if (key == '#') {
                // Phím # dùng để Xác nhận Mật khẩu (Enter)
                if (strcmp(entered_pass, CORRECT_PASS) == 0) {
                    process_correct_access("Password"); // Gọi hàm mở cửa
                } else if (device_config.temp_key[0] != '\0' && strcmp(entered_pass, device_config.temp_key) == 0) {
                    clear_temp_key();
                    process_correct_access("Temp Key");
                } else {
                    if (process_wrong_access()) { // Sai đủ ngưỡng thì chụp ảnh gửi cảnh báo
                        capture_and_send_alert("keypad_failed_4_times");
                    }
                }
                // Xóa mảng để chuẩn bị cho lần nhập sau
                memset(entered_pass, 0, sizeof(entered_pass));
                pass_len = 0;
            } 
            else {
                // Nếu bấm số bình thường
                if (pass_len == 0) {
                    lcd_clear(); lcd_put_cur(0, 0); lcd_send_string("Nhap mat khau:");
                }
                if (pass_len < 15) {
                    entered_pass[pass_len] = key;
                    pass_len++;
                    
                    // In dấu * để che độ dài mật khẩu trên LCD
                    lcd_put_cur(1, 0);
                    for(int i = 0; i < pass_len; i++) lcd_send_data('*');
                }
            }
        }

        
        vTaskDelay(pdMS_TO_TICKS(10));
    }
}
