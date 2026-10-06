#ifndef PTROCOS_SHELL_H
#define PTROCOS_SHELL_H
#include <stdint.h>
#define SHELL_ARGS 8
enum shell_parse_result {SHELL_OK,SHELL_QUOTE_ERROR,SHELL_ESCAPE_ERROR,SHELL_TOO_MANY_ARGS};
// In-place parse; quotes/backslash removed. argv references the caller's buffer.
int shell_parse(char *line,char **argv,unsigned *argc);
int shell_u32(const char *text,uint32_t *value);
// Completes a unique command prefix, or returns NULL for none/ambiguity.
const char *shell_complete(const char *prefix);
extern const char *const shell_commands[];
extern const unsigned shell_command_count;
#endif
