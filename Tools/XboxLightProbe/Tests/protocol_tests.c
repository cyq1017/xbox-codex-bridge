#include "../xbox_light_protocol.h"

#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static void test_builds_constant_on_packet(void) {
  uint8_t packet[XBOX_LIGHT_PACKET_SIZE] = {0};
  const uint8_t expected[XBOX_LIGHT_PACKET_SIZE] = {
      0x0a, 0x20, 0x01, 0x03, 0x00, 0x01, 0x14,
  };

  const int result = xbox_light_build_packet(
      packet, sizeof(packet), XBOX_LIGHT_MODE_ON, 20, 1);

  assert(result == XBOX_LIGHT_PACKET_SIZE);
  assert(memcmp(packet, expected, sizeof(expected)) == 0);
}

static void test_rejects_brightness_above_hardware_limit(void) {
  uint8_t packet[XBOX_LIGHT_PACKET_SIZE] = {0};

  const int result = xbox_light_build_packet(
      packet, sizeof(packet), XBOX_LIGHT_MODE_ON,
      XBOX_LIGHT_MAX_BRIGHTNESS + 1, 1);

  assert(result == XBOX_LIGHT_ERROR_BRIGHTNESS);
}

static void test_rejects_unknown_mode(void) {
  uint8_t packet[XBOX_LIGHT_PACKET_SIZE] = {0};

  const int result =
      xbox_light_build_packet(packet, sizeof(packet), 0xff, 20, 1);

  assert(result == XBOX_LIGHT_ERROR_MODE);
}

int main(void) {
  test_builds_constant_on_packet();
  test_rejects_brightness_above_hardware_limit();
  test_rejects_unknown_mode();
  puts("protocol tests passed");
  return 0;
}
