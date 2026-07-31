#include "../xbox_light_options.h"

#include <assert.h>
#include <stdbool.h>
#include <stdio.h>

static void test_defaults_to_dry_run(void) {
  const char *arguments[] = {"xbox-light-probe"};
  struct xbox_light_options options = {0};

  const int result = xbox_light_parse_options(1, arguments, &options);

  assert(result == XBOX_LIGHT_OPTIONS_OK);
  assert(options.execute == false);
}

static void test_rejects_removed_visual_test_flag(void) {
  const char *arguments[] = {"xbox-light-probe", "--visual-test"};
  struct xbox_light_options options = {0};

  const int result = xbox_light_parse_options(2, arguments, &options);

  assert(result == XBOX_LIGHT_OPTIONS_ERROR_UNKNOWN_FLAG);
}

static void test_execute_requires_explicit_disconnect_acknowledgement(void) {
  const char *arguments[] = {"xbox-light-probe", "--execute"};
  struct xbox_light_options options = {0};

  const int result = xbox_light_parse_options(2, arguments, &options);

  assert(result == XBOX_LIGHT_OPTIONS_ERROR_ACK_REQUIRED);
}

static void test_execute_is_enabled_only_with_both_flags(void) {
  const char *arguments[] = {"xbox-light-probe", "--execute",
                             "--acknowledge-temporary-disconnect"};
  struct xbox_light_options options = {0};

  const int result = xbox_light_parse_options(3, arguments, &options);

  assert(result == XBOX_LIGHT_OPTIONS_OK);
  assert(options.execute == true);
}

static void test_execute_requires_root(void) {
  struct xbox_light_options options = {.execute = true};

  assert(xbox_light_execution_allowed(&options, 501) == false);
  assert(xbox_light_execution_allowed(&options, 0) == true);
}

int main(void) {
  test_defaults_to_dry_run();
  test_rejects_removed_visual_test_flag();
  test_execute_requires_explicit_disconnect_acknowledgement();
  test_execute_is_enabled_only_with_both_flags();
  test_execute_requires_root();
  puts("options tests passed");
  return 0;
}
