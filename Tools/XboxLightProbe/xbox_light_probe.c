#include "xbox_light_endpoint.h"
#include "xbox_light_options.h"
#include "xbox_light_protocol.h"

#include <libusb.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sysexits.h>
#include <unistd.h>

enum {
  XBOX_VENDOR_ID = 0x045e,
  XBOX_SERIES_PRODUCT_ID = 0x0b12,
  XBOX_DATA_INTERFACE = 0,
  XBOX_TRANSFER_TIMEOUT_MILLISECONDS = 1000,
  XBOX_MAX_ENDPOINTS = 32,
};

static void print_packet(const uint8_t *packet, size_t packet_size) {
  fputs("packet:", stdout);
  for (size_t index = 0; index < packet_size; index++) {
    printf(" %02x", packet[index]);
  }
  fputc('\n', stdout);
}

static int find_interrupt_output_endpoint(
    const struct libusb_config_descriptor *configuration,
    uint8_t *selected_address) {
  struct xbox_light_endpoint endpoints[XBOX_MAX_ENDPOINTS] = {0};
  size_t endpoint_count = 0;

  for (uint8_t interface_index = 0;
       interface_index < configuration->bNumInterfaces; interface_index++) {
    const struct libusb_interface *interface =
        &configuration->interface[interface_index];

    for (int alternate_index = 0;
         alternate_index < interface->num_altsetting; alternate_index++) {
      const struct libusb_interface_descriptor *alternate =
          &interface->altsetting[alternate_index];

      for (uint8_t endpoint_index = 0;
           endpoint_index < alternate->bNumEndpoints; endpoint_index++) {
        if (endpoint_count >= XBOX_MAX_ENDPOINTS) {
          return XBOX_LIGHT_ENDPOINT_NOT_FOUND;
        }

        const struct libusb_endpoint_descriptor *endpoint =
            &alternate->endpoint[endpoint_index];
        endpoints[endpoint_count++] = (struct xbox_light_endpoint){
            .interface_number = alternate->bInterfaceNumber,
            .alternate_setting = alternate->bAlternateSetting,
            .address = endpoint->bEndpointAddress,
            .attributes = endpoint->bmAttributes & LIBUSB_TRANSFER_TYPE_MASK,
        };
      }
    }
  }

  return xbox_light_select_output_endpoint(endpoints, endpoint_count,
                                           selected_address);
}

static int restore_driver(libusb_device_handle *handle, bool detached) {
  if (!detached) {
    return LIBUSB_SUCCESS;
  }

  const int result =
      libusb_attach_kernel_driver(handle, XBOX_DATA_INTERFACE);
  if (result != LIBUSB_SUCCESS) {
    fprintf(stderr, "failed to restore Apple driver: %s\n",
            libusb_error_name(result));
  }
  return result;
}

static int send_packet_once(const uint8_t *packet, int packet_size) {
  libusb_context *context = NULL;
  libusb_device_handle *handle = NULL;
  struct libusb_config_descriptor *configuration = NULL;
  bool detached = false;
  bool claimed = false;
  int result = libusb_init(&context);
  int operation_result = LIBUSB_ERROR_OTHER;

  if (result != LIBUSB_SUCCESS) {
    fprintf(stderr, "libusb initialization failed: %s\n",
            libusb_error_name(result));
    return result;
  }

  handle = libusb_open_device_with_vid_pid(context, XBOX_VENDOR_ID,
                                            XBOX_SERIES_PRODUCT_ID);
  if (handle == NULL) {
    fputs("Xbox Series controller 045e:0b12 was not found\n", stderr);
    operation_result = LIBUSB_ERROR_NO_DEVICE;
    goto cleanup;
  }

  result = libusb_get_active_config_descriptor(libusb_get_device(handle),
                                                &configuration);
  if (result != LIBUSB_SUCCESS) {
    fprintf(stderr, "could not read USB configuration: %s\n",
            libusb_error_name(result));
    operation_result = result;
    goto cleanup;
  }

  uint8_t endpoint_address = 0;
  result = find_interrupt_output_endpoint(configuration, &endpoint_address);
  libusb_free_config_descriptor(configuration);
  configuration = NULL;
  if (result != XBOX_LIGHT_ENDPOINT_OK) {
    fputs("interface 0 interrupt OUT endpoint was not found\n", stderr);
    operation_result = LIBUSB_ERROR_NOT_FOUND;
    goto cleanup;
  }

  const int driver_active =
      libusb_kernel_driver_active(handle, XBOX_DATA_INTERFACE);
  if (driver_active == 1) {
    fputs("temporarily detaching the Apple Xbox driver...\n", stdout);
    result = libusb_detach_kernel_driver(handle, XBOX_DATA_INTERFACE);
    if (result != LIBUSB_SUCCESS) {
      fprintf(stderr, "driver detach failed: %s\n",
              libusb_error_name(result));
      operation_result = result;
      goto cleanup;
    }
    detached = true;
  } else if (driver_active < 0 && driver_active != LIBUSB_ERROR_NOT_SUPPORTED) {
    fprintf(stderr, "could not inspect driver state: %s\n",
            libusb_error_name(driver_active));
    operation_result = driver_active;
    goto cleanup;
  }

  result = libusb_claim_interface(handle, XBOX_DATA_INTERFACE);
  if (result != LIBUSB_SUCCESS) {
    fprintf(stderr, "interface claim failed: %s\n",
            libusb_error_name(result));
    operation_result = result;
    goto cleanup;
  }
  claimed = true;

  int transferred = 0;
  result = libusb_interrupt_transfer(
      handle, endpoint_address, (unsigned char *)packet, packet_size,
      &transferred, XBOX_TRANSFER_TIMEOUT_MILLISECONDS);
  if (result != LIBUSB_SUCCESS) {
    fprintf(stderr, "LED transfer failed: %s\n", libusb_error_name(result));
    operation_result = result;
    goto cleanup;
  }
  if (transferred != packet_size) {
    fprintf(stderr, "LED transfer was incomplete: %d of %d bytes\n",
            transferred, packet_size);
    operation_result = LIBUSB_ERROR_IO;
    goto cleanup;
  }

  puts("LED packet accepted by the USB endpoint");
  operation_result = LIBUSB_SUCCESS;

cleanup:
  if (configuration != NULL) {
    libusb_free_config_descriptor(configuration);
  }
  if (claimed) {
    const int release_result =
        libusb_release_interface(handle, XBOX_DATA_INTERFACE);
    if (release_result != LIBUSB_SUCCESS &&
        operation_result == LIBUSB_SUCCESS) {
      fprintf(stderr, "interface release failed: %s\n",
              libusb_error_name(release_result));
      operation_result = release_result;
    }
  }
  if (handle != NULL) {
    const int restore_result = restore_driver(handle, detached);
    if (restore_result != LIBUSB_SUCCESS &&
        operation_result == LIBUSB_SUCCESS) {
      operation_result = restore_result;
    }
    libusb_close(handle);
  }
  libusb_exit(context);
  return operation_result;
}

int main(int argument_count, const char *const arguments[]) {
  struct xbox_light_options options = {0};
  const int options_result =
      xbox_light_parse_options(argument_count, arguments, &options);

  if (options_result == XBOX_LIGHT_OPTIONS_ERROR_ACK_REQUIRED) {
    fputs("--acknowledge-temporary-disconnect is required with --execute\n",
          stderr);
    return EX_USAGE;
  }
  if (options_result != XBOX_LIGHT_OPTIONS_OK) {
    fputs("usage: xbox-light-probe [--execute "
          "--acknowledge-temporary-disconnect]\n",
          stderr);
    return EX_USAGE;
  }

  uint8_t packet[XBOX_LIGHT_PACKET_SIZE] = {0};
  const int packet_result = xbox_light_build_packet(
      packet, sizeof(packet), XBOX_LIGHT_MODE_ON, 20, 1);
  if (packet_result != XBOX_LIGHT_PACKET_SIZE) {
    fputs("failed to build the known-safe LED packet\n", stderr);
    return EX_SOFTWARE;
  }

  puts("target: Microsoft Xbox Series Controller 045e:0b12");
  print_packet(packet, sizeof(packet));

  if (!options.execute) {
    puts("DRY RUN: no USB access performed");
    return EX_OK;
  }

  if (!xbox_light_execution_allowed(&options, (unsigned int)geteuid())) {
    fputs("execution requires root\n", stderr);
    return EX_NOPERM;
  }

  const int send_result = send_packet_once(packet, sizeof(packet));
  return send_result == LIBUSB_SUCCESS ? EX_OK : EX_IOERR;
}
