#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "d9mtmetal.h"
int main(int argc, char **argv) {
  @autoreleasepool {
    if (argc != 2) return 2;
    void *handle = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!handle) { fprintf(stderr, "dlopen: %s\n", dlerror()); return 1; }
    int (**calls)(void *) = dlsym(handle, "__wine_unix_call_funcs");
    if (!calls) { fprintf(stderr, "Missing Unix call table\n"); return 1; }
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) { fprintf(stderr, "No Metal device available\n"); return 1; }
    const char *source = "#include <metal_stdlib>\nusing namespace metal;\nkernel void smoke(device float *out [[buffer(0)]], uint i [[thread_position_in_grid]]) { out[i] = 42.0f; }";
    struct d9mt_library_params p = {0};
    p.device = (uint64_t)(uintptr_t)device;
    p.source_ptr = (uint64_t)(uintptr_t)source;
    p.source_len = strlen(source);
    p.source_kind = D9MT_SOURCE_MSL_TEXT;
    int result = calls[D9MT_FUNC_LIBRARY_FOR_KEY](&p);
    id<MTLLibrary> library = (id<MTLLibrary>)(uintptr_t)p.ret_library;
    if (result || !library) { fprintf(stderr, "Shader compile failed: %s\n", [[(NSError *)(uintptr_t)p.ret_error description] UTF8String]); return 1; }
    id<MTLFunction> function = [library newFunctionWithName:@"smoke"];
    NSError *error = nil;
    id<MTLComputePipelineState> pipeline = [device newComputePipelineStateWithFunction:function error:&error];
    if (!pipeline) { fprintf(stderr, "Pipeline failed: %s\n", [[error description] UTF8String]); return 1; }
    id<MTLBuffer> buffer = [device newBufferWithLength:sizeof(float) options:MTLResourceStorageModeShared];
    id<MTLCommandQueue> queue = [device newCommandQueue];
    id<MTLCommandBuffer> command = [queue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [command computeCommandEncoder];
    [encoder setComputePipelineState:pipeline];
    [encoder setBuffer:buffer offset:0 atIndex:0];
    [encoder dispatchThreads:MTLSizeMake(1,1,1) threadsPerThreadgroup:MTLSizeMake(1,1,1)];
    [encoder endEncoding]; [command commit]; [command waitUntilCompleted];
    if (command.status != MTLCommandBufferStatusCompleted || *(float *)buffer.contents != 42.0f) { fprintf(stderr, "Metal compute/readback failed\n"); return 1; }
    printf("PASS: D9MT companion loaded under Rosetta; shader compiled, GPU executed, result read back on %s.\n", [[device name] UTF8String]);
  }
  return 0;
}
