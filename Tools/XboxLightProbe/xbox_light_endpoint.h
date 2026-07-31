#ifndef XBOX_LIGHT_ENDPOINT_H
#define XBOX_LIGHT_ENDPOINT_H

#include <stddef.h>
#include <stdint.h>

enum {
  XBOX_LIGHT_ENDPOINT_OK = 0,
  XBOX_LIGHT_ENDPOINT_NOT_FOUND = -1,
  XBOX_LIGHT_ENDPOINT_INVALID_ARGUMENT = -2,
  XBOX_LIGHT_TRANSFER_BULK = 0x02,
  XBOX_LIGHT_TRANSFER_INTERRUPT = 0x03,
};

struct xbox_light_endpoint {
  uint8_t interface_number;
  uint8_t alternate_setting;
  uint8_t address;
  uint8_t attributes;
};

int xbox_light_select_output_endpoint(
    const struct xbox_light_endpoint *endpoints, size_t endpoint_count,
    uint8_t *selected_address);

#endif
