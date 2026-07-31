#include "../xbox_light_endpoint.h"

#include <assert.h>
#include <stdint.h>
#include <stdio.h>

static void test_selects_only_data_interface_interrupt_out_endpoint(void) {
  const struct xbox_light_endpoint endpoints[] = {
      {.interface_number = 0,
       .alternate_setting = 0,
       .address = 0x82,
       .attributes = XBOX_LIGHT_TRANSFER_INTERRUPT},
      {.interface_number = 1,
       .alternate_setting = 1,
       .address = 0x03,
       .attributes = XBOX_LIGHT_TRANSFER_INTERRUPT},
      {.interface_number = 0,
       .alternate_setting = 0,
       .address = 0x02,
       .attributes = XBOX_LIGHT_TRANSFER_INTERRUPT},
  };
  uint8_t selected = 0;

  const int result = xbox_light_select_output_endpoint(
      endpoints, sizeof(endpoints) / sizeof(endpoints[0]), &selected);

  assert(result == XBOX_LIGHT_ENDPOINT_OK);
  assert(selected == 0x02);
}

static void test_rejects_non_interrupt_output_endpoint(void) {
  const struct xbox_light_endpoint endpoints[] = {
      {.interface_number = 0,
       .alternate_setting = 0,
       .address = 0x02,
       .attributes = XBOX_LIGHT_TRANSFER_BULK},
  };
  uint8_t selected = 0;

  const int result = xbox_light_select_output_endpoint(
      endpoints, sizeof(endpoints) / sizeof(endpoints[0]), &selected);

  assert(result == XBOX_LIGHT_ENDPOINT_NOT_FOUND);
}

int main(void) {
  test_selects_only_data_interface_interrupt_out_endpoint();
  test_rejects_non_interrupt_output_endpoint();
  puts("endpoint tests passed");
  return 0;
}
