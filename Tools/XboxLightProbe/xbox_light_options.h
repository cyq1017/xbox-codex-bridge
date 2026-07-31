#ifndef XBOX_LIGHT_OPTIONS_H
#define XBOX_LIGHT_OPTIONS_H

#include <stdbool.h>

enum {
  XBOX_LIGHT_OPTIONS_OK = 0,
  XBOX_LIGHT_OPTIONS_ERROR_ARGUMENT = -1,
  XBOX_LIGHT_OPTIONS_ERROR_ACK_REQUIRED = -2,
  XBOX_LIGHT_OPTIONS_ERROR_UNKNOWN_FLAG = -3,
};

struct xbox_light_options {
  bool execute;
};

int xbox_light_parse_options(int argument_count,
                             const char *const arguments[],
                             struct xbox_light_options *options);

bool xbox_light_execution_allowed(const struct xbox_light_options *options,
                                  unsigned int effective_user_id);

#endif
