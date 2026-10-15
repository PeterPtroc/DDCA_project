
#include "app_api.h"

static void print(const struct ptrocos_app_api* api, const char* s) {
  unsigned len = 0;
  while (s[len]) len++;
  api->write(s, len);
}

static void print_number(const struct ptrocos_app_api* api, unsigned n) {
  char buf[10];
  unsigned i = 10;

  do {
    buf[--i] = '0' + n % 10;
    n /= 10;
  } while (n);

  api->write(buf + i, 10 - i);
}

int app_main(const struct ptrocos_app_api* api, int argc,
             const char* const* argv) {
  (void)argc;
  (void)argv;

  if (!api || api->version != 1) return 1;

  unsigned count = 0;

  for (unsigned n = 2; n <= 1000; n++) {
    int prime = 1;

    for (unsigned d = 2; d * d <= n; d++) {
      if (n % d == 0) {
        prime = 0;
        break;
      }
    }

    if (prime) count++;

    if (n % 100 == 0) api->yield();
  }

  print(api, "Primes1000: ");
  print_number(api, count);
  print(api, "\r\n");

  return 0;
}
