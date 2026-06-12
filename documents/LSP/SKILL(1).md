---
name: esp32-patterns
description: ESP32 C/C++ patterns and idioms. Load when designing components, working with FreeRTOS (tasks/queues/semaphores/timers), writing peripheral drivers (GPIO/SPI/I2C/UART), using NVS, managing memory regions (DRAM/IRAM/DMA), or writing C++ safely under ESP-IDF constraints.
compatibility: opencode
metadata:
  domain: embedded
  framework: esp-idf
---

## When to load this skill

Load when:
- Designing a new ESP-IDF component from scratch
- Working with FreeRTOS primitives — tasks, queues, semaphores, event groups, timers
- Implementing GPIO (especially with ISRs), SPI, I2C, or UART
- Persisting configuration to NVS
- Hitting memory errors, heap exhaustion, or DMA allocation failures
- Writing C++ in an IDF project and needing safe patterns
- Asking "what is the right ESP32 way to do X"

---

## Component Structure

```
my_component/
├── CMakeLists.txt
├── Kconfig              # optional — adds menuconfig options
├── include/
│   └── my_component.h  # Public API only — no implementation details
└── my_component.c      # Implementation
```

**CMakeLists.txt:**
```cmake
idf_component_register(
    SRCS
        "my_component.c"
    INCLUDE_DIRS
        "include"           # Public headers — exposed to all dependents
    PRIV_INCLUDE_DIRS
        "."                 # Private headers — this component only
    REQUIRES
        freertos            # Public deps — propagated transitively
        esp_log
    PRIV_REQUIRES
        driver              # Private deps — only this component's .c files need them
        nvs_flash
)
```

**Kconfig:**
```kconfig
menu "My Component"
    config MY_TASK_STACK_SIZE
        int "Task stack size (bytes)"
        default 4096
    config MY_BUFFER_SIZE
        int "Buffer size (bytes)"
        default 256
endmenu
```

Access in code: `#include "sdkconfig.h"` → `CONFIG_MY_TASK_STACK_SIZE`

---

## FreeRTOS Tasks

```c
static void my_task(void *pvParameters) {
    my_config_t *cfg = (my_config_t *)pvParameters;

    for (;;) {
        // work here
        vTaskDelay(pdMS_TO_TICKS(100));   // ALWAYS use pdMS_TO_TICKS, never raw ticks
    }
    // Tasks must not return. To exit: vTaskDelete(NULL);
}

TaskHandle_t task_handle;
BaseType_t ret = xTaskCreatePinnedToCore(
    my_task,           // function
    "my_task",         // name shown in vTaskList()
    CONFIG_MY_TASK_STACK_SIZE,   // stack bytes (not words)
    &my_config,        // pvParameters — must outlive the task
    5,                 // priority: 1=low, configMAX_PRIORITIES-1=max
    &task_handle,      // NULL if handle not needed
    APP_CPU_NUM        // PRO_CPU_NUM=0, APP_CPU_NUM=1
);
if (ret != pdPASS) {
    ESP_LOGE(TAG, "Task creation failed: %d", ret);
}
```

**Profile stack usage from inside the task:**
```c
UBaseType_t hwm = uxTaskGetHighWaterMark(NULL);
ESP_LOGI(TAG, "Stack HWM: %u words remaining", hwm);
// < 64 words remaining → danger. Double the stack.
```

**Priority guidelines:**
- Idle task: 0 (never assign)
- Background/non-critical: 1–3
- Normal application tasks: 4–6
- Driver/ISR-deferred tasks: 7–10
- Time-critical (WiFi, BT): 11+ (system tasks use these)
- Never use `configMAX_PRIORITIES - 1` for application tasks

---

## Queues (Cross-task Communication)

```c
// Define a message type
typedef struct {
    uint32_t gpio_num;
    int64_t  timestamp_us;
} gpio_event_t;

// Create once (typically in app_main or component init)
QueueHandle_t gpio_queue = xQueueCreate(
    10,                  // max items in queue
    sizeof(gpio_event_t) // item size — queue copies by value
);

// Producer — safe from task or ISR
gpio_event_t evt = { .gpio_num = 0, .timestamp_us = esp_timer_get_time() };
// From task:
xQueueSend(gpio_queue, &evt, portMAX_DELAY);
// From ISR (non-blocking, never use portMAX_DELAY in ISR):
BaseType_t woken = pdFALSE;
xQueueSendFromISR(gpio_queue, &evt, &woken);
portYIELD_FROM_ISR(woken);  // yield if higher-priority task was unblocked

// Consumer task
gpio_event_t received;
if (xQueueReceive(gpio_queue, &received, pdMS_TO_TICKS(500)) == pdTRUE) {
    ESP_LOGI(TAG, "GPIO %lu triggered at %lld us", received.gpio_num, received.timestamp_us);
}
```

---

## Semaphores and Mutexes

```c
// Binary semaphore — signaling (ISR → task, or task → task)
SemaphoreHandle_t data_ready = xSemaphoreCreateBinary();

// Signal (from ISR):
BaseType_t woken = pdFALSE;
xSemaphoreGiveFromISR(data_ready, &woken);
portYIELD_FROM_ISR(woken);

// Wait (in task):
if (xSemaphoreTake(data_ready, pdMS_TO_TICKS(1000)) == pdTRUE) {
    // data is ready
}

// Mutex — mutual exclusion (NEVER use from ISR)
SemaphoreHandle_t mutex = xSemaphoreCreateMutex();
xSemaphoreTake(mutex, portMAX_DELAY);  // acquire
// ... critical section ...
xSemaphoreGive(mutex);                  // release

// Counting semaphore — resource pools
SemaphoreHandle_t slots = xSemaphoreCreateCounting(5, 5);  // max=5, initial=5
xSemaphoreTake(slots, portMAX_DELAY);  // acquire one slot
xSemaphoreGive(slots);                  // release slot
```

---

## Event Groups (Multi-bit Synchronization)

```c
EventGroupHandle_t system_events = xEventGroupCreate();

// Define bits with clear names
#define EVT_WIFI_UP     (1 << 0)
#define EVT_MQTT_UP     (1 << 1)
#define EVT_NVS_READY   (1 << 2)
#define EVT_ALL_READY   (EVT_WIFI_UP | EVT_MQTT_UP | EVT_NVS_READY)

// Set from any task (or xEventGroupSetBitsFromISR from ISR)
xEventGroupSetBits(system_events, EVT_WIFI_UP);

// Wait for all required subsystems
EventBits_t bits = xEventGroupWaitBits(
    system_events,
    EVT_ALL_READY,   // wait for these bits
    pdFALSE,         // don't clear on exit (pdTRUE to auto-clear)
    pdTRUE,          // wait for ALL bits (pdFALSE = any one bit)
    portMAX_DELAY
);
```

---

## GPIO

```c
#include "driver/gpio.h"

// Output
gpio_set_direction(GPIO_NUM_2, GPIO_MODE_OUTPUT);
gpio_set_level(GPIO_NUM_2, 1);

// Input with interrupt
gpio_config_t cfg = {
    .pin_bit_mask = (1ULL << GPIO_NUM_0),
    .mode         = GPIO_MODE_INPUT,
    .pull_up_en   = GPIO_PULLUP_ENABLE,
    .intr_type    = GPIO_INTR_NEGEDGE,
};
gpio_config(&cfg);

// ISR RULES: IRAM_ATTR required, no heap alloc, no blocking calls, fast only
static void IRAM_ATTR gpio_isr(void *arg) {
    uint32_t gpio_num = (uint32_t)(uintptr_t)arg;
    BaseType_t woken = pdFALSE;
    xQueueSendFromISR(gpio_queue, &gpio_num, &woken);
    portYIELD_FROM_ISR(woken);   // wake the consumer task
}

gpio_install_isr_service(0);                             // call once
gpio_isr_handler_add(GPIO_NUM_0, gpio_isr, (void *)0);  // per pin
```

---

## SPI Master

```c
#include "driver/spi_master.h"

spi_bus_config_t bus = {
    .mosi_io_num  = PIN_MOSI,
    .miso_io_num  = PIN_MISO,
    .sclk_io_num  = PIN_CLK,
    .quadwp_io_num = -1,
    .quadhd_io_num = -1,
    .max_transfer_sz = 4096,
};
ESP_ERROR_CHECK(spi_bus_initialize(SPI2_HOST, &bus, SPI_DMA_CH_AUTO));

spi_device_interface_config_t dev = {
    .clock_speed_hz = 1 * 1000 * 1000,  // 1 MHz
    .mode           = 0,                  // CPOL=0, CPHA=0
    .spics_io_num   = PIN_CS,
    .queue_size     = 7,
};
spi_device_handle_t spi;
ESP_ERROR_CHECK(spi_bus_add_device(SPI2_HOST, &dev, &spi));

// Blocking transaction
spi_transaction_t t = {
    .length    = 8 * tx_len,  // LENGTH IN BITS
    .tx_buffer = tx_buf,
    .rx_buffer = rx_buf,      // NULL if write-only
};
ESP_ERROR_CHECK(spi_device_transmit(spi, &t));
```

---

## I2C Master (IDF ≥ v5.1 new API)

```c
#include "driver/i2c_master.h"

i2c_master_bus_config_t bus_cfg = {
    .i2c_port             = I2C_NUM_0,
    .sda_io_num           = PIN_SDA,
    .scl_io_num           = PIN_SCL,
    .clk_source           = I2C_CLK_SRC_DEFAULT,
    .glitch_ignore_cnt    = 7,
    .flags.enable_internal_pullup = true,
};
i2c_master_bus_handle_t bus;
ESP_ERROR_CHECK(i2c_new_master_bus(&bus_cfg, &bus));

i2c_device_config_t dev_cfg = {
    .dev_addr_length = I2C_ADDR_BIT_LEN_7,
    .device_address  = 0x68,    // 7-bit address
    .scl_speed_hz    = 400000,  // 400kHz Fast Mode
};
i2c_master_dev_handle_t dev;
ESP_ERROR_CHECK(i2c_master_bus_add_device(bus, &dev_cfg, &dev));

// Write register address, read back data
uint8_t reg = 0x3B;
uint8_t buf[6];
ESP_ERROR_CHECK(i2c_master_transmit_receive(dev, &reg, 1, buf, 6, pdMS_TO_TICKS(100)));
```

*If on IDF < v5.1, use the legacy `i2c_master_write_to_device` / `i2c_master_read_from_device` API.*

---

## NVS (Non-Volatile Storage)

```c
#include "nvs_flash.h"
#include "nvs.h"

// Initialize once at boot — typically in app_main
esp_err_t err = nvs_flash_init();
if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
    ESP_ERROR_CHECK(nvs_flash_erase());   // erase and retry
    err = nvs_flash_init();
}
ESP_ERROR_CHECK(err);

// Write
nvs_handle_t h;
ESP_ERROR_CHECK(nvs_open("storage", NVS_READWRITE, &h));
ESP_ERROR_CHECK(nvs_set_u32(h, "boot_count", 42));
ESP_ERROR_CHECK(nvs_set_str(h, "device_id", "abc-123"));
ESP_ERROR_CHECK(nvs_commit(h));
nvs_close(h);

// Read
ESP_ERROR_CHECK(nvs_open("storage", NVS_READONLY, &h));
uint32_t val = 0;
err = nvs_get_u32(h, "boot_count", &val);
if (err == ESP_ERR_NVS_NOT_FOUND) {
    val = 0;   // default
} else {
    ESP_ERROR_CHECK(err);
}
nvs_close(h);
```

---

## Memory Regions

| Region | Location | Use for |
|---|---|---|
| DRAM | Internal SRAM | Heap, task stacks, regular variables |
| IRAM | Internal SRAM (instruction) | ISR handlers, speed-critical code |
| PSRAM | External SPI RAM | Large buffers (if PSRAM fitted) |
| Flash (XIP) | External SPI Flash | Code and read-only data |

```c
// IRAM placement for ISRs and their callees
void IRAM_ATTR fast_function(void) { ... }
static const char TAG[] = "MY_COMPONENT";   // string in flash (default, fine for tasks)

// DMA-capable allocation — required for SPI/I2C DMA buffers
uint8_t *buf = (uint8_t *)heap_caps_malloc(len, MALLOC_CAP_DMA | MALLOC_CAP_INTERNAL);
if (buf == NULL) {
    ESP_LOGE(TAG, "DMA alloc failed for %zu bytes", len);
    return ESP_ERR_NO_MEM;
}
// ... use buf ...
heap_caps_free(buf);

// Heap diagnostics
ESP_LOGI(TAG, "Free heap: %lu  Min free: %lu",
    esp_get_free_heap_size(),
    esp_get_minimum_free_heap_size());

// Check DMA-capable heap specifically
ESP_LOGI(TAG, "Free DMA heap: %zu",
    heap_caps_get_free_size(MALLOC_CAP_DMA));
```

---

## C++ Safe Patterns for ESP32

**ESP-IDF C++ constraints (defaults):**
- Exceptions disabled (`-fno-exceptions`) — use `esp_err_t` return codes
- RTTI disabled — no `dynamic_cast`, no `typeid`
- `new`/`delete` work but skip constructors/destructors for global objects
- `std::thread` allocates unknown stack — prefer FreeRTOS tasks directly
- `std::string` and STL containers use heap — safe in tasks, dangerous in ISRs

```cpp
// RAII mutex guard — zero overhead, exception-safe even without exceptions
class MutexGuard {
    SemaphoreHandle_t &m_;
public:
    explicit MutexGuard(SemaphoreHandle_t &m) : m_(m) {
        xSemaphoreTake(m_, portMAX_DELAY);
    }
    ~MutexGuard() { xSemaphoreGive(m_); }
    MutexGuard(const MutexGuard &) = delete;
    MutexGuard &operator=(const MutexGuard &) = delete;
};

// Usage: mutex released automatically when scope exits
{
    MutexGuard lock(shared_mutex);
    shared_data.value = 42;
}   // ← xSemaphoreGive called here
```

```cpp
// Type-safe GPIO wrapper — zero runtime cost, catches wrong pin numbers at compile time
template<gpio_num_t PIN, gpio_mode_t MODE = GPIO_MODE_OUTPUT>
class GpioPin {
public:
    GpioPin() { gpio_set_direction(PIN, MODE); }
    void set(bool high) requires (MODE == GPIO_MODE_OUTPUT) {
        gpio_set_level(PIN, high ? 1 : 0);
    }
    bool get() const { return gpio_get_level(PIN) != 0; }
};

GpioPin<GPIO_NUM_2> status_led;
GpioPin<GPIO_NUM_0, GPIO_MODE_INPUT> boot_button;
status_led.set(true);
bool pressed = !boot_button.get();
```

```cpp
// Global object initialization pitfall — avoid in ESP32
// BAD: constructor runs before app_main, heap may not be ready
static MyDriver driver;   // ← dangerous

// GOOD: lazy singleton pattern
MyDriver &get_driver() {
    static MyDriver *instance = nullptr;
    if (instance == nullptr) {
        instance = new MyDriver();   // allocated after heap is ready
    }
    return *instance;
}
```

---

## Common Bugs Cheatsheet

| Symptom | Root cause | Fix |
|---|---|---|
| Crash: `LoadProhibited` | Null pointer dereference | Check all pointers before use |
| Crash: `StoreProhibited` | Write to flash (XIP) memory | Move variable to DRAM |
| `Guru Meditation: Unhandled debug exception` | Stack overflow | Increase task stack; profile with `uxTaskGetHighWaterMark` |
| `Task watchdog got triggered` | Task blocking without yield | Add `vTaskDelay(1)` or use `portYIELD()` in tight loops |
| Corrupt SPI/I2C data | Non-DMA-capable buffer | Use `heap_caps_malloc(..., MALLOC_CAP_DMA)` |
| Random crash from ISR | Missing `IRAM_ATTR` | Add `IRAM_ATTR` to ISR and all functions it calls |
| ISR calls blocking API | Calling `vTaskDelay`, `xSemaphoreTake` from ISR | Use `...FromISR()` variants; defer work via queue |
| Global C++ object crash before `app_main` | Static init order / heap not ready | Use lazy init singleton instead |
| `printf` from ISR | Not safe in interrupt context | Use `ets_printf` or better: queue to task |
| NVS write fails with `ESP_ERR_NVS_NO_FREE_PAGES` | NVS partition full | Erase and reinit, or reserve larger NVS partition |

---

## ESP_ERROR_CHECK Pattern

Always wrap ESP-IDF API calls that return `esp_err_t`:
```c
// In production code — panics on error with file/line info
ESP_ERROR_CHECK(spi_bus_initialize(SPI2_HOST, &bus, SPI_DMA_CH_AUTO));

// When you want to handle errors gracefully
esp_err_t err = some_api_call();
if (err != ESP_OK) {
    ESP_LOGE(TAG, "API failed: %s", esp_err_to_name(err));
    return err;   // propagate
}

// Log-only (don't abort) — useful in cleanup paths
ESP_ERROR_CHECK_WITHOUT_ABORT(nvs_close(handle));
```
