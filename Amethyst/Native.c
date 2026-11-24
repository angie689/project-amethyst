#include "Native.h"
#include <errno.h>
#include <mach/mach.h>
#include <sys/mount.h>

int am_task_memory(uint64_t *resident, uint64_t *virtualSize, uint64_t *footprint) {
    task_vm_info_data_t info = {0};
    mach_msg_type_number_t size = TASK_VM_INFO_COUNT;
    kern_return_t status = task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &size);
    if (status != KERN_SUCCESS) return status;
    if (size < TASK_VM_INFO_REV1_COUNT) return KERN_NOT_SUPPORTED;
    *resident = info.resident_size;
    *virtualSize = info.virtual_size;
    *footprint = info.phys_footprint;
    return KERN_SUCCESS;
}

int am_thread_count(unsigned *count) {
    thread_act_array_t threads = NULL;
    mach_msg_type_number_t n = 0;
    kern_return_t status = task_threads(mach_task_self(), &threads, &n);
    if (status != KERN_SUCCESS) return status;
    *count = n;
    for (unsigned i = 0; i < n; i++) mach_port_deallocate(mach_task_self(), threads[i]);
    vm_deallocate(mach_task_self(), (vm_address_t)threads, n * sizeof(thread_t));
    return KERN_SUCCESS;
}

int am_volume(const char *path, uint64_t *total, uint64_t *available) {
    struct statfs info;
    if (statfs(path, &info) < 0) return errno;
    *total = info.f_blocks * (uint64_t)info.f_bsize;
    *available = info.f_bavail * (uint64_t)info.f_bsize;
    return 0;
}
