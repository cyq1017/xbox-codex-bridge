#include "xbox_light_endpoint.h"

int xbox_light_select_output_endpoint(
    const struct xbox_light_endpoint *endpoints, size_t endpoint_count,
    uint8_t *selected_address) {
  if (endpoints == NULL || selected_address == NULL) {
    return XBOX_LIGHT_ENDPOINT_INVALID_ARGUMENT;
  }

  for (size_t index = 0; index < endpoint_count; index++) {
    const struct xbox_light_endpoint endpoint = endpoints[index];
    const int is_output = (endpoint.address & 0x80) == 0;

    if (endpoint.interface_number == 0 && endpoint.alternate_setting == 0 &&
        endpoint.attributes == XBOX_LIGHT_TRANSFER_INTERRUPT && is_output) {
      *selected_address = endpoint.address;
      return XBOX_LIGHT_ENDPOINT_OK;
    }
  }

  return XBOX_LIGHT_ENDPOINT_NOT_FOUND;
}
