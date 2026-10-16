#include <moonbit.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>

/* Validation runner only: input is a local UTF-8 JSON file selected by the
 * Python harness. Bytes is borrowed and NUL-terminated by the MoonBit runtime. */
MOONBIT_FFI_EXPORT moonbit_bytes_t yrs_trace_read_file(moonbit_bytes_t path) {
  FILE *file = fopen((const char *)path, "rb");
  if (!file) { perror("open trace"); exit(EXIT_FAILURE); }
  if (fseek(file, 0, SEEK_END)) { fclose(file); exit(EXIT_FAILURE); }
  long length = ftell(file);
  if (length < 0 || length > INT_MAX || fseek(file, 0, SEEK_SET)) {
    fclose(file); fputs("invalid trace file size\n", stderr); exit(EXIT_FAILURE);
  }
  moonbit_bytes_t bytes = moonbit_make_bytes((int32_t)length, 0);
  if (fread(bytes, 1, (size_t)length, file) != (size_t)length) {
    fclose(file); moonbit_decref(bytes); fputs("cannot read trace\n", stderr);
    exit(EXIT_FAILURE);
  }
  fclose(file);
  return bytes;
}
