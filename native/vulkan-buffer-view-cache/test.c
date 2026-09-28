#define MVC_TESTING 1
#include "layer.c"
#include <assert.h>
#include <sched.h>
#include <stdio.h>
static atomic_uint_fast64_t made, destroyed;
static atomic_uchar was_destroyed[COUNT * 6 + 50000];
static VkResult VKAPI_CALL mock_create(VkDevice d, const VkBufferViewCreateInfo *c,
                                       const VkAllocationCallbacks *a, VkBufferView *out) {
    (void)d;
    (void)c;
    (void)a;
    uint64_t value = ++made;
    assert(value < sizeof(was_destroyed) / sizeof(was_destroyed[0]));
    *out = (VkBufferView)(uintptr_t)value;
    return VK_SUCCESS;
}
static void VKAPI_CALL mock_destroy(VkDevice d, VkBufferView view, const VkAllocationCallbacks *a) {
    (void)d;
    (void)a;
    if (!view)
        return;
    assert(!atomic_exchange(&was_destroyed[(uintptr_t)view], 1));
    destroyed++;
}
static void VKAPI_CALL mock_buffer(VkDevice d, VkBuffer b, const VkAllocationCallbacks *a) {
    (void)d;
    (void)b;
    (void)a;
}
static void VKAPI_CALL mock_device(VkDevice d, const VkAllocationCallbacks *a) {
    (void)d;
    (void)a;
}
static PFN_vkVoidFunction VKAPI_CALL mock_proc(VkDevice d, const char *n) {
    (void)d;
    if (!strcmp(n, "vkCreateBufferView"))
        return (PFN_vkVoidFunction)mock_create;
    if (!strcmp(n, "vkDestroyBufferView"))
        return (PFN_vkVoidFunction)mock_destroy;
    if (!strcmp(n, "vkDestroyBuffer"))
        return (PFN_vkVoidFunction)mock_buffer;
    if (!strcmp(n, "vkDestroyDevice"))
        return (PFN_vkVoidFunction)mock_device;
    return NULL;
}
static void *stress_thread(void *argument) {
    (void)argument;
    VkDevice d = (VkDevice)1;
    for (unsigned i = 0; i < 2000; i++) {
        VkBufferViewCreateInfo c = {.sType = VK_STRUCTURE_TYPE_BUFFER_VIEW_CREATE_INFO,
                                    .buffer = (VkBuffer)42,
                                    .format = VK_FORMAT_R32_UINT,
                                    .offset = (i % 128) * 256,
                                    .range = 16};
        VkBufferView a, b;
        assert(cached_create(d, &c, NULL, &a) == VK_SUCCESS);
        assert(cached_create(d, &c, NULL, &b) == VK_SUCCESS && a == b);
        assert(!atomic_load(&was_destroyed[(uintptr_t)a]));
        sched_yield();
        cached_destroy(d, a, NULL);
        assert(!atomic_load(&was_destroyed[(uintptr_t)b]));
        sched_yield();
        cached_destroy(d, b, NULL);
    }
    return NULL;
}
int main(void) {
    enabled = 1;
    DeviceDispatch second = {.device = (VkDevice)2, .gdpa = mock_proc};
    DeviceDispatch first = {.device = (VkDevice)1, .gdpa = mock_proc, .next = &second};
    devices = &first;
    VkDevice d = (VkDevice)1;
    VkBufferViewCreateInfo c = {.sType = VK_STRUCTURE_TYPE_BUFFER_VIEW_CREATE_INFO,
                                .buffer = (VkBuffer)7,
                                .format = VK_FORMAT_R32_UINT,
                                .range = 4};
    VkBufferView a, b;
    assert(cached_create(d, &c, NULL, &a) == VK_SUCCESS);
    assert(cached_create(d, &c, NULL, &b) == VK_SUCCESS && a == b && made == 1);
    cached_destroy(d, a, NULL);
    assert(destroyed == 0);
    cached_destroy(d, b, NULL);
    assert(destroyed == 0);
    assert(cached_create(d, &c, NULL, &b) == VK_SUCCESS && b == a && made == 1);
    cached_destroy_buffer(d, c.buffer, NULL);
    assert(destroyed == 0);
    assert(cached_create(d, &c, NULL, &a) == VK_SUCCESS && a != b);
    cached_destroy(d, b, NULL);
    assert(destroyed == 1);
    cached_destroy(d, a, NULL);
    cached_destroy_buffer(d, c.buffer, NULL);
    assert(live == 0 && made == destroyed);
    for (unsigned i = 0; i < COUNT * 5 + 3; i++) {
        c.offset = i * 256;
        assert(cached_create(d, &c, NULL, &a) == VK_SUCCESS);
        cached_destroy(d, a, NULL);
        assert(live <= COUNT);
    }
    cached_destroy_device(d, NULL);
    assert(live == 0 && made == destroyed);
    c.offset = 0;
    assert(cached_create(d, &c, NULL, &a) == VK_SUCCESS);
    c.range = 8;
    assert(cached_create(d, &c, NULL, &b) == VK_SUCCESS && a != b);
    cached_destroy(d, b, NULL);
    c.range = 4;
    assert(cached_create((VkDevice)2, &c, NULL, &b) == VK_SUCCESS && a != b);
    cached_destroy((VkDevice)2, b, NULL);
    cached_destroy_device((VkDevice)2, NULL);
    enabled = 0;
    assert(cached_create(d, &c, NULL, &b) == VK_SUCCESS && a != b);
    cached_destroy(d, a, NULL);
    cached_destroy(d, b, NULL);
    cached_destroy_device(d, NULL);
    assert(live == 0 && made == destroyed);
    enabled = 1;
    atomic_store(&private_data_devices, 1);
    assert(cached_create(d, &c, NULL, &a) == VK_SUCCESS);
    assert(cached_create(d, &c, NULL, &b) == VK_SUCCESS && a != b);
    cached_destroy(d, a, NULL);
    cached_destroy(d, b, NULL);
    assert(live == 0 && made == destroyed);
    atomic_store(&private_data_devices, 0);
    c.pNext = &c;
    assert(cached_create(d, &c, NULL, &a) == VK_SUCCESS);
    assert(cached_create(d, &c, NULL, &b) == VK_SUCCESS && a != b);
    cached_destroy(d, a, NULL);
    cached_destroy(d, b, NULL);
    c.pNext = NULL;
    pthread_t workers[8];
    for (unsigned i = 0; i < 8; i++)
        assert(pthread_create(&workers[i], NULL, stress_thread, NULL) == 0);
    for (unsigned i = 0; i < 8; i++)
        assert(pthread_join(workers[i], NULL) == 0);
    cached_destroy_buffer(d, (VkBuffer)42, NULL);
    assert(live == 0 && made == destroyed);
    puts("shared view layer: lifetime, 8-thread refcounts, retirement, capacity, privateData and "
         "live-mode tests PASS");
    return 0;
}
