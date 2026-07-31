#ifndef XBOX_LIGHT_PROTOCOL_H
#define XBOX_LIGHT_PROTOCOL_H

#include <stddef.h>
#include <stdint.h>

enum {
  XBOX_LIGHT_PACKET_SIZE = 7,
  XBOX_LIGHT_MAX_BRIGHTNESS = 50,
  XBOX_LIGHT_ERROR_BUFFER = -1,
  XBOX_LIGHT_ERROR_MODE = -2,
  XBOX_LIGHT_ERROR_BRIGHTNESS = -3,
};

enum xbox_light_mode {
  XBOX_LIGHT_MODE_OFF = 0x00,
  XBOX_LIGHT_MODE_ON = 0x01,
  XBOX_LIGHT_MODE_BLINK_FAST = 0x02,
  XBOX_LIGHT_MODE_BLINK_NORMAL = 0x03,
  XBOX_LIGHT_MODE_BLINK_SLOW = 0x04,
  XBOX_LIGHT_MODE_FADE_SLOW = 0x08,
  XBOX_LIGHT_MODE_FADE_FAST = 0x09,
};

int xbox_light_build_packet(uint8_t *output, size_t output_size,
                            uint8_t mode, uint8_t brightness,
                            uint8_t sequence);

#endif
