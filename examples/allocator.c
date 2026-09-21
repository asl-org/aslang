#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <sys/mman.h>

typedef struct
{
    uint8_t *memory; // Raw base pointer from mmap
    size_t capacity; // 1 GB total limit
    size_t bump_ptr; // Current allocation cursor (moves forward)
} HeapStackAllocator;

// --- Initialize and Lock Physical Memory ---
HeapStackAllocator *stack_allocator_init(size_t total_size)
{
    HeapStackAllocator *allocator = malloc(sizeof(HeapStackAllocator));
    if (!allocator)
        return NULL;

    // MAP_POPULATE immediately faults-in and claims real physical RAM pages.
    // This removes lazy allocation and prevents subsequent mid-run write failures.
    allocator->memory = mmap(NULL, total_size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_POPULATE, -1, 0);

    if (allocator->memory == MAP_FAILED)
    {
        perror("Fatal Error: System failed to provision 1GB physical backing memory.");
        free(allocator);
        return NULL;
    }

    allocator->capacity = total_size;
    allocator->bump_ptr = 0;

    return allocator;
}

// --- O(1) Stack Allocation (Bump Allocation) ---
// Two CPU instructions: Check boundary, shift pointer.
void *stack_alloc(HeapStackAllocator *allocator, size_t size)
{
    // 8-byte alignment optimization to protect CPU SIMD/register efficiency
    size = (size + 7) & ~7;

    // Strict boundary enforcement
    if (allocator->bump_ptr + size > allocator->capacity)
    {
        return NULL; // Stack Overflow: Compiler allocation invariant violated
    }

    void *alloc_ptr = &allocator->memory[allocator->bump_ptr];
    allocator->bump_ptr += size; // Move the bump pointer up

    return alloc_ptr;
}

// --- O(1) Stack Release (Popping the Stack) ---
// One CPU instruction: Reset pointer back to a saved historical watermark.
void stack_release(HeapStackAllocator *allocator, size_t saved_watermark)
{
    // Basic safety validation: Never allow popping past the bottom of the stack
    if (saved_watermark <= allocator->bump_ptr)
    {
        allocator->bump_ptr = saved_watermark;
    }
}

void stack_allocator_destroy(HeapStackAllocator *allocator)
{
    if (!allocator)
        return;
    munmap(allocator->memory, allocator->capacity);
    free(allocator);
}

// --- Compiler Code-Generation Flow Simulation ---
int main()
{
    HeapStackAllocator *runtime_stack = stack_allocator_init(1024 * 1024 * 1024);
    if (!runtime_stack)
        return 1;

    printf("Heap-Allocated Stack Allocator initialized with 1GB physical RAM.\n\n");

    // --- STEP 1: Compiler enters a functional execution block ---
    // The compiler saves the current stack watermark before evaluating an expression
    size_t watermark_v1 = runtime_stack->bump_ptr;
    printf("[Frame 1 Start] Watermark saved at byte: %zu\n", watermark_v1);

    // Allocate an immutable struct cluster
    int *data_cluster = (int *)stack_alloc(runtime_stack, sizeof(int) * 4);
    if (!data_cluster)
    {
        printf("Allocation Failed!\n");
        return 1;
    }

    data_cluster[0] = 42;
    printf("Allocated structural payload at memory address: %p\n", (void *)data_cluster);
    printf("Current stack cursor position: %zu bytes\n", runtime_stack->bump_ptr);

    // --- STEP 2: Compiler enters a nested evaluation block ---
    size_t watermark_v2 = runtime_stack->bump_ptr;
    printf("\n[Frame 2 Start] Nested Watermark saved at byte: %zu\n", watermark_v2);

    // Allocate structural sharing nodes (e.g., an updated HAMT path branch)
    char *text_node = (char *)stack_alloc(runtime_stack, 128);
    strcpy(text_node, "Structural Sharing Path Node");
    printf("Allocated nested node at memory address: %p\n", (void *)text_node);
    printf("Current stack cursor position: %zu bytes\n", runtime_stack->bump_ptr);

    // --- STEP 3: Expression evaluation finishes ---
    // Lifetime analysis determines the nested text_node is out of scope.
    // The compiler auto-injects a release to pop the stack back to watermark_v2.
    stack_release(runtime_stack, watermark_v2);
    printf("\n[Frame 2 Released] Stack popped back to byte: %zu\n", runtime_stack->bump_ptr);

    // The parent block finishes, popping all the way back to the start.
    stack_release(runtime_stack, watermark_v1);
    printf("[Frame 1 Released] Stack popped back to base: %zu\n", runtime_stack->bump_ptr);

    stack_allocator_destroy(runtime_stack);
    return 0;
}
