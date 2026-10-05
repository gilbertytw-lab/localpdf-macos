#include "pdfium/fpdfview.h"
#include "pdfium/fpdf_edit.h"
#include "pdfium/fpdf_save.h"
#include "pdfium/fpdf_text.h"
#include "pdfium/fpdf_transformpage.h"

// Owns the returned buffer. Free it with LPDF_Free after copying.
int LPDF_Save(FPDF_DOCUMENT document, unsigned char **data, size_t *size);
void LPDF_Free(void *data);
