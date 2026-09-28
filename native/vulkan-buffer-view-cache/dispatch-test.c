#define MVC_TESTING 1
#include "layer.c"
#include <assert.h>

typedef struct {
    void *dispatch;
} Handle;
static Handle instance_handles[2], physical_handles[2], device_handles[2];
static unsigned instances_created, instances_destroyed, devices_created, devices_destroyed;
static int creation_fails;

static VkResult VKAPI_CALL next_create_instance(const VkInstanceCreateInfo *info,
                                                const VkAllocationCallbacks *a, VkInstance *out) {
    (void)a;
    const VkLayerInstanceCreateInfo *chain = info->pNext;
    assert(chain->u.pLayerInfo == NULL);
    if (creation_fails)
        return VK_ERROR_OUT_OF_HOST_MEMORY;
    unsigned index = instances_created++;
    assert(index < 2);
    instance_handles[index].dispatch = &instance_handles[index];
    physical_handles[index].dispatch = instance_handles[index].dispatch;
    *out = (VkInstance)&instance_handles[index];
    return VK_SUCCESS;
}
static void VKAPI_CALL next_destroy_instance(VkInstance instance, const VkAllocationCallbacks *a) {
    (void)instance;
    (void)a;
    instances_destroyed++;
}
static VkResult VKAPI_CALL next_create_device(VkPhysicalDevice physical,
                                              const VkDeviceCreateInfo *info,
                                              const VkAllocationCallbacks *a, VkDevice *out) {
    (void)a;
    const VkLayerDeviceCreateInfo *chain = info->pNext;
    assert(chain->u.pLayerInfo == NULL);
    unsigned index = physical == (VkPhysicalDevice)&physical_handles[0] ? 0 : 1;
    device_handles[index].dispatch = &device_handles[index];
    *out = (VkDevice)&device_handles[index];
    devices_created++;
    return VK_SUCCESS;
}
static void VKAPI_CALL next_destroy_device(VkDevice device, const VkAllocationCallbacks *a) {
    (void)device;
    (void)a;
    devices_destroyed++;
}
static VkResult VKAPI_CALL next_extensions(VkPhysicalDevice p, const char *name, uint32_t *count,
                                           VkExtensionProperties *properties) {
    (void)properties;
    assert(p == (VkPhysicalDevice)&physical_handles[1]);
    assert(name == NULL);
    *count = 7;
    return VK_SUCCESS;
}
static PFN_vkVoidFunction VKAPI_CALL next_gdpa(VkDevice d, const char *name) {
    assert(d == (VkDevice)&device_handles[0] || d == (VkDevice)&device_handles[1]);
    if (!strcmp(name, "vkDestroyDevice"))
        return (PFN_vkVoidFunction)next_destroy_device;
    return NULL;
}
static PFN_vkVoidFunction VKAPI_CALL next_gipa(VkInstance instance, const char *name) {
    if (!strcmp(name, "vkCreateInstance")) {
        assert(instance == VK_NULL_HANDLE);
        return (PFN_vkVoidFunction)next_create_instance;
    }
    assert(instance == (VkInstance)&instance_handles[0] ||
           instance == (VkInstance)&instance_handles[1]);
    if (!strcmp(name, "vkCreateDevice"))
        return (PFN_vkVoidFunction)next_create_device;
    if (!strcmp(name, "vkDestroyInstance"))
        return (PFN_vkVoidFunction)next_destroy_instance;
    if (!strcmp(name, "vkEnumerateDeviceExtensionProperties"))
        return (PFN_vkVoidFunction)next_extensions;
    return NULL;
}

int main(void) {
    uint32_t count = 0;
    assert(vkEnumerateInstanceLayerProperties(&count, NULL) == VK_SUCCESS && count == 1);
    VkLayerProperties properties;
    count = 0;
    assert(vkEnumerateInstanceLayerProperties(&count, &properties) == VK_INCOMPLETE);
    count = 1;
    assert(vkEnumerateInstanceLayerProperties(&count, &properties) == VK_SUCCESS);
    assert(!strcmp(properties.layerName, LAYER_NAME));
    assert(vkGetInstanceProcAddr(NULL, "vkUnknown") == NULL);
    assert(vkGetDeviceProcAddr(NULL, NULL) == NULL);
    layer_destroy_instance(NULL, NULL);
    layer_destroy_device(NULL, NULL);

    VkInstance created_instances[2];
    VkDevice created_devices[2];
    for (unsigned index = 0; index < 2; index++) {
        VkLayerInstanceLink link = {.pfnNextGetInstanceProcAddr = next_gipa};
        VkLayerInstanceCreateInfo chain = {.sType = VK_STRUCTURE_TYPE_LOADER_INSTANCE_CREATE_INFO,
                                           .function = VK_LAYER_LINK_INFO,
                                           .u.pLayerInfo = &link};
        VkInstanceCreateInfo info = {.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
                                     .pNext = &chain};
        if (index == 0) {
            creation_fails = 1;
            assert(layer_create_instance(&info, NULL, &created_instances[index]) ==
                   VK_ERROR_OUT_OF_HOST_MEMORY);
            assert(instances == NULL);
            creation_fails = 0;
            chain.u.pLayerInfo = &link;
        }
        assert(layer_create_instance(&info, NULL, &created_instances[index]) == VK_SUCCESS);
        assert(vkGetInstanceProcAddr(created_instances[index], "vkUnknown") == NULL);
        VkPhysicalDevicePrivateDataFeatures private_features = {
            .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PRIVATE_DATA_FEATURES,
            .privateData = index == 1};
        VkLayerDeviceLink device_link = {.pfnNextGetInstanceProcAddr = next_gipa,
                                         .pfnNextGetDeviceProcAddr = next_gdpa};
        VkLayerDeviceCreateInfo device_chain = {.sType =
                                                    VK_STRUCTURE_TYPE_LOADER_DEVICE_CREATE_INFO,
                                                .pNext = &private_features,
                                                .function = VK_LAYER_LINK_INFO,
                                                .u.pLayerInfo = &device_link};
        VkDeviceCreateInfo device_info = {.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
                                          .pNext = &device_chain};
        assert(layer_create_device((VkPhysicalDevice)&physical_handles[index], &device_info, NULL,
                                   &created_devices[index]) == VK_SUCCESS);
        assert(vkGetDeviceProcAddr(created_devices[index], "vkDestroyDevice") ==
               (PFN_vkVoidFunction)layer_destroy_device);
        assert(vkGetDeviceProcAddr(created_devices[index], "vkUnsupported") == NULL);
    }
    assert(atomic_load(&private_data_devices) == 1);
    assert(vkEnumerateDeviceExtensionProperties((VkPhysicalDevice)&physical_handles[1], NULL,
                                                &count, NULL) == VK_SUCCESS &&
           count == 7);
    layer_destroy_device(created_devices[1], NULL);
    assert(atomic_load(&private_data_devices) == 0);
    layer_destroy_instance(created_instances[1], NULL);
    assert(instances->instance == created_instances[0]);
    layer_destroy_device(created_devices[0], NULL);
    layer_destroy_instance(created_instances[0], NULL);
    assert(instances == NULL && devices == NULL);
    assert(instances_created == 2 && instances_destroyed == 2 && devices_created == 2 &&
           devices_destroyed == 2);
    puts("Vulkan layer dispatch: independent instances/devices, forwarding, failure and "
         "privateData PASS");
}
