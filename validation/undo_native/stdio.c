#include <moonbit.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Validation-only JSON-lines transport; the CRDT implementation stays in the
 * same MoonBit package used by the JavaScript runner. No retained C pointers. */
MOONBIT_FFI_EXPORT moonbit_bytes_t yrs_undo_read_line(void) {
  size_t length = 0, capacity = 4096;
  unsigned char *buffer = malloc(capacity);
  if (!buffer) { perror("allocate input"); exit(EXIT_FAILURE); }
  int ch;
  while ((ch = fgetc(stdin)) != EOF && ch != '\n') {
    if (length == capacity) {
      if (capacity == INT_MAX) {
        free(buffer); fputs("input line too large\n", stderr); exit(EXIT_FAILURE);
      }
      capacity = capacity > INT_MAX / 2 ? INT_MAX : capacity * 2;
      unsigned char *next = realloc(buffer, capacity);
      if (!next) { free(buffer); perror("grow input"); exit(EXIT_FAILURE); }
      buffer = next;
    }
    buffer[length++] = (unsigned char)ch;
  }
  if (ferror(stdin)) { free(buffer); perror("read input"); exit(EXIT_FAILURE); }
  moonbit_bytes_t bytes = moonbit_make_bytes((int32_t)length, 0);
  if (length) memcpy(bytes, buffer, length);
  free(buffer);
  return bytes;
}

MOONBIT_FFI_EXPORT void yrs_undo_flush_output(void) {
  if (fflush(stdout)) { perror("flush output"); exit(EXIT_FAILURE); }
}
