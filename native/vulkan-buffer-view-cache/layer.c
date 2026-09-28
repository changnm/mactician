#define _GNU_SOURCE
#include <pthread.h>
#include <vulkan/vk_layer.h>
#include <vulkan/vulkan.h>
#ifdef __ANDROID__
#include <android/log.h>
#include <sys/system_properties.h>
#else
#include <stdio.h>
#define ANDROID_LOG_INFO 4
#define ANDROID_LOG_ERROR 6
#define __android_log_print(priority, tag, ...)                                                    \
    ((void)(priority), (void)(tag), fprintf(stderr, __VA_ARGS__))
#endif
#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// Process-local cache. Only ordinary views without custom
// allocation/pNext participate; buffers and devices purge their views first.
// Identical non-dispatchable handles may be shared when privateData is disabled.
// Retain one driver object until all client references are released; incompatible
// private-data devices bypass caching before entering this path.
#ifndef BUCKETS
#define BUCKETS 16384
#endif
#define WAYS 4
#define COUNT (BUCKETS * WAYS)
#define TAG "MacticianVkView"
typedef struct {
    VkDevice device;
    VkBuffer buffer;
    VkBufferView view;
    VkDeviceSize offset, range;
    VkFormat format;
    VkBufferViewCreateFlags flags;
    unsigned refs;
    int retired;
    uint64_t stamp;
    int next, buffer_next, buffer_prev;
} Entry;
static Entry entries[COUNT];
static int heads[BUCKETS], buffer_heads[BUCKETS];
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_once_t once = PTHREAD_ONCE_INIT;
static atomic_int enabled;
static int initial_mode;
#ifndef MVC_TESTING
static _Thread_local unsigned poll_tick;
#endif
static uint64_t requests, hits, misses, drops, live, clock_tick;
typedef struct InstanceDispatch {
    VkInstance instance;
    void *key;
    PFN_vkGetInstanceProcAddr gipa;
    struct InstanceDispatch *next;
} InstanceDispatch;
typedef struct DeviceDispatch {
    VkDevice device;
    PFN_vkGetDeviceProcAddr gdpa;
    int private_data;
    struct DeviceDispatch *next;
} DeviceDispatch;
static InstanceDispatch *instances;
static DeviceDispatch *devices;
static atomic_uint private_data_devices;
static pthread_mutex_t dispatch_lock = PTHREAD_MUTEX_INITIALIZER;
static PFN_vkVoidFunction instance_proc(VkInstance instance, void *physical_key, const char *name) {
    PFN_vkGetInstanceProcAddr gipa = NULL;
    pthread_mutex_lock(&dispatch_lock);
    for (InstanceDispatch *p = instances; p; p = p->next) {
        if ((instance && p->instance == instance) || (physical_key && p->key == physical_key)) {
            instance = p->instance;
            gipa = p->gipa;
            break;
        }
    }
    pthread_mutex_unlock(&dispatch_lock);
    return gipa ? gipa(instance, name) : NULL;
}

static uint64_t mix(uint64_t x) {
    x ^= x >> 30;
    x *= UINT64_C(0xbf58476d1ce4e5b9);
    x ^= x >> 27;
    x *= UINT64_C(0x94d049bb133111eb);
    return x ^ (x >> 31);
}
static unsigned view_bucket(VkBufferView v) { return mix((uintptr_t)v) & (BUCKETS - 1); }
static unsigned buffer_bucket(VkDevice d, VkBuffer b) {
    return (mix((uintptr_t)d) ^ mix((uintptr_t)b)) & (BUCKETS - 1);
}
static void stats(void) {
    __android_log_print(ANDROID_LOG_INFO, TAG,
                        "enabled=%d requests=%llu hits=%llu misses=%llu evictions=%llu cached=%llu",
                        enabled, (unsigned long long)requests, (unsigned long long)hits,
                        (unsigned long long)misses, (unsigned long long)drops,
                        (unsigned long long)live);
}
static void init(void) {
    for (unsigned i = 0; i < BUCKETS; i++)
        heads[i] = buffer_heads[i] = -1;
    enabled = 1;
    initial_mode = 1;
    __android_log_print(ANDROID_LOG_INFO, TAG, "layer_initialized enabled=1 capacity=%d", COUNT);
}
static int current_mode(void) {
#ifndef MVC_TESTING
    if ((poll_tick++ & 63u) == 0) {
        char value[PROP_VALUE_MAX] = {0};
        int length = __system_property_get("debug.mactician.vk_view_cache", value);
        int next =
            (length == 1 && (value[0] == '0' || value[0] == '1')) ? value[0] - '0' : initial_mode;
        if (atomic_exchange(&enabled, next) != next)
            __android_log_print(ANDROID_LOG_INFO, TAG, "mode_changed enabled=%d", next);
    }
#endif
    return atomic_load(&enabled);
}
static PFN_vkVoidFunction proc(VkDevice d, const char *name) {
    PFN_vkGetDeviceProcAddr gdpa = NULL;
    pthread_mutex_lock(&dispatch_lock);
    for (DeviceDispatch *p = devices; p; p = p->next)
        if (p->device == d) {
            gdpa = p->gdpa;
            break;
        }
    pthread_mutex_unlock(&dispatch_lock);
    return gdpa ? gdpa(d, name) : NULL;
}
static void remove_entry(unsigned index) {
    Entry *e = &entries[index];
    unsigned b = view_bucket(e->view);
    int *p = &heads[b];
    while (*p >= 0 && (unsigned)*p != index)
        p = &entries[*p].next;
    if (*p >= 0)
        *p = e->next;
    if (e->buffer_prev >= 0)
        entries[e->buffer_prev].buffer_next = e->buffer_next;
    else
        buffer_heads[buffer_bucket(e->device, e->buffer)] = e->buffer_next;
    if (e->buffer_next >= 0)
        entries[e->buffer_next].buffer_prev = e->buffer_prev;
    PFN_vkDestroyBufferView destroy =
        (PFN_vkDestroyBufferView)proc(e->device, "vkDestroyBufferView");
    destroy(e->device, e->view, NULL);
    memset(e, 0, sizeof(*e));
    live--;
}
static VkResult VKAPI_CALL cached_create(VkDevice d, const VkBufferViewCreateInfo *c,
                                         const VkAllocationCallbacks *a, VkBufferView *out) {
    PFN_vkCreateBufferView create = (PFN_vkCreateBufferView)proc(d, "vkCreateBufferView");
    if (!create)
        return VK_ERROR_INITIALIZATION_FAILED;
    if (!current_mode() || atomic_load(&private_data_devices) || !c || c->pNext || a || !out)
        return create(d, c, a, out);
    uint64_t key = mix((uintptr_t)d) ^ mix((uintptr_t)c->buffer) ^ mix(c->offset) ^ mix(c->range) ^
                   mix((uint64_t)c->format << 32 | c->flags);
    unsigned base = (key & (BUCKETS - 1)) * WAYS;
    pthread_mutex_lock(&lock);
    requests++;
    int free_index = -1;
    uint64_t oldest = UINT64_MAX;
    for (unsigned i = base; i < base + WAYS; i++) {
        Entry *e = &entries[i];
        if (e->view && e->refs < UINT32_MAX && !e->retired && e->device == d &&
            e->buffer == c->buffer && e->offset == c->offset && e->range == c->range &&
            e->format == c->format && e->flags == c->flags) {
            e->refs++;
            e->stamp = ++clock_tick;
            *out = e->view;
            hits++;
            if (requests % 4096 == 0)
                stats();
            pthread_mutex_unlock(&lock);
            return VK_SUCCESS;
        }
        if (!e->view) {
            free_index = i;
            oldest = 0;
        } else if (!e->refs && e->stamp < oldest) {
            free_index = i;
            oldest = e->stamp;
        }
    }
    misses++;
    VkResult r = create(d, c, a, out);
    if (r == VK_SUCCESS && free_index >= 0) {
        Entry *e = &entries[free_index];
        if (e->view) {
            remove_entry(free_index);
            drops++;
        }
        *e = (Entry){.device = d,
                     .buffer = c->buffer,
                     .view = *out,
                     .offset = c->offset,
                     .range = c->range,
                     .format = c->format,
                     .flags = c->flags,
                     .refs = 1,
                     .stamp = ++clock_tick};
        unsigned b = view_bucket(*out);
        e->next = heads[b];
        heads[b] = free_index;
        unsigned bb = buffer_bucket(d, c->buffer);
        e->buffer_prev = -1;
        e->buffer_next = buffer_heads[bb];
        if (e->buffer_next >= 0)
            entries[e->buffer_next].buffer_prev = free_index;
        buffer_heads[bb] = free_index;
        live++;
    }
    if (requests % 4096 == 0)
        stats();
    pthread_mutex_unlock(&lock);
    return r;
}
static void VKAPI_CALL cached_destroy(VkDevice d, VkBufferView v, const VkAllocationCallbacks *a) {
    PFN_vkDestroyBufferView destroy = (PFN_vkDestroyBufferView)proc(d, "vkDestroyBufferView");
    if (!v || a) {
        destroy(d, v, a);
        return;
    }
    pthread_mutex_lock(&lock);
    for (int i = heads[view_bucket(v)]; i >= 0; i = entries[i].next) {
        Entry *e = &entries[i];
        if (e->device == d && e->view == v) {
            if (e->refs) {
                e->refs--;
                e->stamp = ++clock_tick;
                if (!e->refs && e->retired)
                    remove_entry(i);
            } else
                __android_log_print(ANDROID_LOG_ERROR, TAG, "duplicate destroy detected");
            pthread_mutex_unlock(&lock);
            return;
        }
    }
    pthread_mutex_unlock(&lock);
    destroy(d, v, a);
}
static void VKAPI_CALL cached_destroy_buffer(VkDevice d, VkBuffer b,
                                             const VkAllocationCallbacks *a) {
    {
        pthread_mutex_lock(&lock);
        for (int i = buffer_heads[buffer_bucket(d, b)]; i >= 0;) {
            int next = entries[i].buffer_next;
            if (entries[i].device == d && entries[i].buffer == b) {
                if (!entries[i].refs)
                    remove_entry(i);
                else
                    entries[i].retired = 1;
            }
            i = next;
        }
        pthread_mutex_unlock(&lock);
    }
    ((PFN_vkDestroyBuffer)proc(d, "vkDestroyBuffer"))(d, b, a);
}
static void VKAPI_CALL cached_destroy_device(VkDevice d, const VkAllocationCallbacks *a) {
    {
        pthread_mutex_lock(&lock);
        for (unsigned i = 0; i < COUNT; i++)
            if (entries[i].view && entries[i].device == d)
                remove_entry(i);
        stats();
        pthread_mutex_unlock(&lock);
    }
    ((PFN_vkDestroyDevice)proc(d, "vkDestroyDevice"))(d, a);
}

#define EXPORT __attribute__((visibility("default")))
#define LAYER_NAME "VK_LAYER_MACTICIAN_buffer_view_cache"
EXPORT VkResult VKAPI_CALL vkEnumerateInstanceLayerProperties(uint32_t *count,
                                                              VkLayerProperties *properties) {
    if (!properties) {
        *count = 1;
        return VK_SUCCESS;
    }
    if (!*count)
        return VK_INCOMPLETE;
    *properties = (VkLayerProperties){.layerName = LAYER_NAME,
                                      .specVersion = VK_API_VERSION_1_3,
                                      .implementationVersion = 1,
                                      .description = "Mactician buffer view cache"};
    *count = 1;
    return VK_SUCCESS;
}
EXPORT VkResult VKAPI_CALL vkEnumerateDeviceLayerProperties(VkPhysicalDevice p, uint32_t *count,
                                                            VkLayerProperties *properties) {
    (void)p;
    return vkEnumerateInstanceLayerProperties(count, properties);
}
EXPORT VkResult VKAPI_CALL
vkEnumerateInstanceExtensionProperties(const char *name, uint32_t *count,
                                       VkExtensionProperties *properties) {
    (void)properties;
    if (name && strcmp(name, LAYER_NAME))
        return VK_ERROR_LAYER_NOT_PRESENT;
    *count = 0;
    return VK_SUCCESS;
}
EXPORT VkResult VKAPI_CALL vkEnumerateDeviceExtensionProperties(VkPhysicalDevice physical,
                                                                const char *name, uint32_t *count,
                                                                VkExtensionProperties *properties) {
    if (name || !physical)
        return vkEnumerateInstanceExtensionProperties(name, count, properties);
    PFN_vkEnumerateDeviceExtensionProperties next =
        (PFN_vkEnumerateDeviceExtensionProperties)instance_proc(
            VK_NULL_HANDLE, *(void **)physical, "vkEnumerateDeviceExtensionProperties");
    return next ? next(physical, name, count, properties) : VK_ERROR_INITIALIZATION_FAILED;
}
static VkResult VKAPI_CALL layer_create_instance(const VkInstanceCreateInfo *info,
                                                 const VkAllocationCallbacks *allocator,
                                                 VkInstance *out) {
    VkLayerInstanceCreateInfo *chain = (VkLayerInstanceCreateInfo *)info->pNext;
    while (chain && (chain->sType != VK_STRUCTURE_TYPE_LOADER_INSTANCE_CREATE_INFO ||
                     chain->function != VK_LAYER_LINK_INFO))
        chain = (VkLayerInstanceCreateInfo *)chain->pNext;
    if (!chain || !chain->u.pLayerInfo)
        return VK_ERROR_INITIALIZATION_FAILED;
    PFN_vkGetInstanceProcAddr gipa = chain->u.pLayerInfo->pfnNextGetInstanceProcAddr;
    PFN_vkCreateInstance create = (PFN_vkCreateInstance)gipa(VK_NULL_HANDLE, "vkCreateInstance");
    if (!create)
        return VK_ERROR_INITIALIZATION_FAILED;
    InstanceDispatch *state = calloc(1, sizeof(*state));
    if (!state)
        return VK_ERROR_OUT_OF_HOST_MEMORY;
    chain->u.pLayerInfo = chain->u.pLayerInfo->pNext;
    VkResult result = create(info, allocator, out);
    if (result != VK_SUCCESS) {
        free(state);
        return result;
    }
    state->instance = *out;
    state->key = *(void **)*out;
    state->gipa = gipa;
    pthread_mutex_lock(&dispatch_lock);
    state->next = instances;
    instances = state;
    pthread_mutex_unlock(&dispatch_lock);
    __android_log_print(ANDROID_LOG_INFO, TAG, "layer_instance_created");
    return result;
}
static void VKAPI_CALL layer_destroy_instance(VkInstance instance,
                                              const VkAllocationCallbacks *allocator) {
    if (!instance)
        return;
    PFN_vkDestroyInstance destroy =
        (PFN_vkDestroyInstance)instance_proc(instance, NULL, "vkDestroyInstance");
    if (destroy)
        destroy(instance, allocator);
    pthread_mutex_lock(&dispatch_lock);
    InstanceDispatch **p = &instances;
    while (*p && (*p)->instance != instance)
        p = &(*p)->next;
    if (*p) {
        InstanceDispatch *old = *p;
        *p = old->next;
        free(old);
    }
    pthread_mutex_unlock(&dispatch_lock);
}
static VkResult VKAPI_CALL layer_create_device(VkPhysicalDevice physical,
                                               const VkDeviceCreateInfo *info,
                                               const VkAllocationCallbacks *allocator,
                                               VkDevice *out) {
    VkLayerDeviceCreateInfo *chain = (VkLayerDeviceCreateInfo *)info->pNext;
    while (chain && (chain->sType != VK_STRUCTURE_TYPE_LOADER_DEVICE_CREATE_INFO ||
                     chain->function != VK_LAYER_LINK_INFO))
        chain = (VkLayerDeviceCreateInfo *)chain->pNext;
    if (!chain || !chain->u.pLayerInfo)
        return VK_ERROR_INITIALIZATION_FAILED;
    PFN_vkCreateDevice create =
        (PFN_vkCreateDevice)instance_proc(VK_NULL_HANDLE, *(void **)physical, "vkCreateDevice");
    if (!create)
        return VK_ERROR_INITIALIZATION_FAILED;
    DeviceDispatch *state = calloc(1, sizeof(*state));
    if (!state)
        return VK_ERROR_OUT_OF_HOST_MEMORY;
    state->gdpa = chain->u.pLayerInfo->pfnNextGetDeviceProcAddr;
    chain->u.pLayerInfo = chain->u.pLayerInfo->pNext;
    VkResult result = create(physical, info, allocator, out);
    if (result != VK_SUCCESS) {
        free(state);
        return result;
    }
    state->device = *out;
    for (const VkBaseInStructure *feature = (const VkBaseInStructure *)info->pNext; feature;
         feature = feature->pNext) {
        if (feature->sType == VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PRIVATE_DATA_FEATURES)
            state->private_data =
                ((const VkPhysicalDevicePrivateDataFeatures *)feature)->privateData != 0;
        if (feature->sType == VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES)
            state->private_data =
                ((const VkPhysicalDeviceVulkan13Features *)feature)->privateData != 0;
    }
    if (state->private_data)
        atomic_fetch_add(&private_data_devices, 1);
    pthread_mutex_lock(&dispatch_lock);
    state->next = devices;
    devices = state;
    pthread_mutex_unlock(&dispatch_lock);
    __android_log_print(ANDROID_LOG_INFO, TAG, "layer_device_created enabled=%d private_data=%d",
                        current_mode(), state->private_data);
    return result;
}
static void VKAPI_CALL layer_destroy_device(VkDevice device,
                                            const VkAllocationCallbacks *allocator) {
    if (!device)
        return;
    cached_destroy_device(device, allocator);
    pthread_mutex_lock(&dispatch_lock);
    DeviceDispatch **p = &devices;
    while (*p && (*p)->device != device)
        p = &(*p)->next;
    if (*p) {
        DeviceDispatch *old = *p;
        *p = old->next;
        if (old->private_data)
            atomic_fetch_sub(&private_data_devices, 1);
        free(old);
    }
    pthread_mutex_unlock(&dispatch_lock);
}
EXPORT PFN_vkVoidFunction VKAPI_CALL vkGetDeviceProcAddr(VkDevice device, const char *name) {
    if (!name)
        return NULL;
    if (!strcmp(name, "vkGetDeviceProcAddr"))
        return (PFN_vkVoidFunction)vkGetDeviceProcAddr;
    PFN_vkVoidFunction original = proc(device, name);
    if (!original)
        return NULL;
    if (!strcmp(name, "vkCreateBufferView"))
        return (PFN_vkVoidFunction)cached_create;
    if (!strcmp(name, "vkDestroyBufferView"))
        return (PFN_vkVoidFunction)cached_destroy;
    if (!strcmp(name, "vkDestroyBuffer"))
        return (PFN_vkVoidFunction)cached_destroy_buffer;
    if (!strcmp(name, "vkDestroyDevice"))
        return (PFN_vkVoidFunction)layer_destroy_device;
    return original;
}
EXPORT PFN_vkVoidFunction VKAPI_CALL vkGetInstanceProcAddr(VkInstance instance, const char *name) {
    if (!name)
        return NULL;
#define COMMAND(n, f)                                                                              \
    if (!strcmp(name, n))                                                                          \
    return (PFN_vkVoidFunction)f
    COMMAND("vkGetInstanceProcAddr", vkGetInstanceProcAddr);
    COMMAND("vkGetDeviceProcAddr", vkGetDeviceProcAddr);
    COMMAND("vkCreateInstance", layer_create_instance);
    COMMAND("vkEnumerateInstanceLayerProperties", vkEnumerateInstanceLayerProperties);
    COMMAND("vkEnumerateDeviceLayerProperties", vkEnumerateDeviceLayerProperties);
    COMMAND("vkEnumerateInstanceExtensionProperties", vkEnumerateInstanceExtensionProperties);
    COMMAND("vkEnumerateDeviceExtensionProperties", vkEnumerateDeviceExtensionProperties);
    if (!instance)
        return NULL;
    COMMAND("vkCreateDevice", layer_create_device);
    COMMAND("vkDestroyInstance", layer_destroy_instance);
    COMMAND("vkDestroyDevice", layer_destroy_device);
    COMMAND("vkCreateBufferView", cached_create);
    COMMAND("vkDestroyBufferView", cached_destroy);
    COMMAND("vkDestroyBuffer", cached_destroy_buffer);
#undef COMMAND
    return instance_proc(instance, NULL, name);
}
__attribute__((constructor)) static void start(void) { pthread_once(&once, init); }
