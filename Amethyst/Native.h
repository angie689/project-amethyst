#pragma once
#include <stdint.h>
#include <zlib.h>

int am_task_memory(uint64_t *resident, uint64_t *virtualSize, uint64_t *footprint);
int am_thread_count(unsigned *count);
int am_volume(const char *path, uint64_t *total, uint64_t *available);

// Decode a single ZIP deflate member into a caller-bounded buffer.
static inline int am_inflate(const uint8_t *src, unsigned size, uint8_t *dst, unsigned capacity) {
    z_stream stream = {0};
    if (inflateInit2(&stream, -MAX_WBITS) != Z_OK) return 0;
    stream.next_in = (Bytef *)src;
    stream.avail_in = size;
    stream.next_out = dst;
    stream.avail_out = capacity;
    int status = inflate(&stream, Z_FINISH);
    int valid = status == Z_STREAM_END && stream.total_out == capacity && stream.total_in == size;
    inflateEnd(&stream);
    return valid;
}
