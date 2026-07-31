#include "xbox_light_options.h"

#include <string.h>

int xbox_light_parse_options(int argument_count,
                             const char *const arguments[],
                             struct xbox_light_options *options) {
  if (argument_count < 1 || arguments == NULL || options == NULL) {
    return XBOX_LIGHT_OPTIONS_ERROR_ARGUMENT;
  }

  bool execute_requested = false;
  bool disconnect_acknowledged = false;

  for (int index = 1; index < argument_count; index++) {
    if (strcmp(arguments[index], "--execute") == 0) {
      execute_requested = true;
    } else if (strcmp(arguments[index],
                      "--acknowledge-temporary-disconnect") == 0) {
      disconnect_acknowledged = true;
    } else {
      return XBOX_LIGHT_OPTIONS_ERROR_UNKNOWN_FLAG;
    }
  }

  if (execute_requested && !disconnect_acknowledged) {
    return XBOX_LIGHT_OPTIONS_ERROR_ACK_REQUIRED;
  }

  options->execute = execute_requested && disconnect_acknowledged;
  return XBOX_LIGHT_OPTIONS_OK;
}

bool xbox_light_execution_allowed(const struct xbox_light_options *options,
                                  unsigned int effective_user_id) {
  if (options == NULL) {
    return false;
  }

  return !options->execute || effective_user_id == 0;
}
