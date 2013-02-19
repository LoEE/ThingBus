typedef size_t buflen_t;

struct buffer {
  uint8_t *data;
  buflen_t start; // first byte containing data (unless start == end)
  buflen_t end;   // first free byte after the data
  buflen_t size;
};

int buffer_ensure (struct buffer *b, buflen_t space);
buflen_t buffer_rpeek (struct buffer *b, uint8_t **s);
void buffer_rseek (struct buffer *b, buflen_t n);
buflen_t buffer_wpeek (struct buffer *b, uint8_t **s);
void buffer_wseek (struct buffer *b, buflen_t n);
int buffer_write (struct buffer *b, const void *s, buflen_t len);
