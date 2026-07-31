#include "xbox_light_protocol.h"

#include <stdbool.h>

static bool xbox_light_mode_is_valid(uint8_t mode) {
  switch (mode) {
  case XBOX_LIGHT_MODE_OFF:
  case XBOX_LIGHT_MODE_ON:
  case XBOX_LIGHT_MODE_BLINK_FAST:
  case XBOX_LIGHT_MODE_BLINK_NORMAL:
  case XBOX_LIGHT_MODE_BLINK_SLOW:
  case XBOX_LIGHT_MODE_FADE_SLOW:
  case XBOX_LIGHT_MODE_FADE_FAST:
    return true;
  default:
    return false;
  }
}

int xbox_light_build_packet(uint8_t *output, size_t output_size,
                            uint8_t mode, uint8_t brightness,
                            uint8_t sequence) {
  if (output == NULL || output_size < XBOX_LIGHT_PACKET_SIZE) {
    return XBOX_LIGHT_ERROR_BUFFER;
  }

  if (!xbox_light_mode_is_valid(mode)) {
    return XBOX_LIGHT_ERROR_MODE;
  }

  if (brightness > XBOX_LIGHT_MAX_BRIGHTNESS) {
    return XBOX_LIGHT_ERROR_BRIGHTNESS;
  }

  output[0] = 0x0a;
  output[1] = 0x20;
  output[2] = sequence;
  output[3] = 0x03;
  output[4] = 0x00;
  output[5] = mode;
  output[6] = brightness;
  return XBOX_LIGHT_PACKET_SIZE;
}
