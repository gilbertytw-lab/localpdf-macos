#include "CPDFium.h"
#include <stdlib.h>
#include <string.h>

typedef struct {
    FPDF_FILEWRITE writer;
    unsigned char *data;
    size_t size;
} MemoryWriter;

static int append(FPDF_FILEWRITE *writer, const void *block, unsigned long size) {
    MemoryWriter *memory = (MemoryWriter *)writer;
    // Bound native serialization separately from the workspace history limit.
    const size_t limit = 128 * 1024 * 1024;
    if (size > limit - memory->size) return 0;
    unsigned char *next = realloc(memory->data, memory->size + size);
    if (!next && size) return 0;
    memory->data = next;
    if (size) memcpy(memory->data + memory->size, block, size);
    memory->size += size;
    return 1;
}

int LPDF_Save(FPDF_DOCUMENT document, unsigned char **data, size_t *size) {
    MemoryWriter memory = {{1, append}, NULL, 0};
    if (!FPDF_SaveAsCopy(document, &memory.writer, FPDF_NO_INCREMENTAL)) {
        free(memory.data);
        return 0;
    }
    *data = memory.data;
    *size = memory.size;
    return 1;
}

void LPDF_Free(void *data) { free(data); }
