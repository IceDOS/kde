// Forwards Sunshine's libvirtualhid evdev devices into a virtual KWin over EIS.
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <libei.h>
#include <linux/input.h>
#include <poll.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <systemd/sd-bus.h>
#include <unistd.h>

#define MAX_INPUTS 3
// KWin's connectToEIS mask: pointer, absolute, keyboard, scroll, button.
#define KWIN_EIS_CAPS (1 | 2 | 4 | 16 | 32)

static const char *const device_names[MAX_INPUTS] = {
    "libvirtualhid Keyboard",
    "libvirtualhid Mouse",
    "libvirtualhid Mouse (Absolute)",
};

struct input {
  int fd;
  bool hires_wheel, hires_hwheel;
  struct input_absinfo abs_x, abs_y;
  double x, y;
  bool abs_pending;
};

static struct input inputs[MAX_INPUTS];
static struct ei_device *pointer, *absolute, *keyboard, *button, *scroll;
static uint32_t sequence;

static bool has_bit(const uint8_t *bits, unsigned bit) {
  return (bits[bit / 8] & (1u << (bit % 8))) != 0;
}

static int connect_eis(sd_bus **bus) {
  sd_bus_error error = SD_BUS_ERROR_NULL;
  sd_bus_message *reply = NULL;
  int fd = -1, cookie = 0;
  if (sd_bus_open_user(bus) < 0 ||
      sd_bus_call_method(*bus, "org.kde.KWin", "/org/kde/KWin/EIS/RemoteDesktop",
                         "org.kde.KWin.EIS.RemoteDesktop", "connectToEIS", &error,
                         &reply, "i", KWIN_EIS_CAPS) < 0 ||
      sd_bus_message_read(reply, "hi", &fd, &cookie) < 0) {
    fprintf(stderr, "connectToEIS failed: %s\n", error.message ? error.message : "no reply");
    sd_bus_error_free(&error);
    return -1;
  }
  // The reply owns its fd; the bus stays open because KWin ties the EIS client to it.
  fd = fcntl(fd, F_DUPFD_CLOEXEC, 3);
  sd_bus_message_unref(reply);
  return fd;
}

static void rescan(void) {
  DIR *dir = opendir("/dev/input");
  if (!dir)
    return;
  for (struct dirent *entry; (entry = readdir(dir));) {
    if (strncmp(entry->d_name, "event", 5) != 0)
      continue;
    char path[300], name[256] = "";
    snprintf(path, sizeof(path), "/dev/input/%s", entry->d_name);
    int fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0)
      continue;
    int slot = -1;
    if (ioctl(fd, EVIOCGNAME(sizeof(name)), name) >= 0)
      for (int i = 0; i < MAX_INPUTS; i++)
        if (inputs[i].fd < 0 && strcmp(name, device_names[i]) == 0)
          slot = i;
    // The grab keeps the host desktop's KWin from also receiving this input.
    if (slot < 0 || ioctl(fd, EVIOCGRAB, 1) < 0) {
      close(fd);
      continue;
    }
    struct input *in = &inputs[slot];
    uint8_t rel[(REL_MAX + 8) / 8] = {0};
    ioctl(fd, EVIOCGBIT(EV_REL, sizeof(rel)), rel);
    in->hires_wheel = has_bit(rel, REL_WHEEL_HI_RES);
    in->hires_hwheel = has_bit(rel, REL_HWHEEL_HI_RES);
    ioctl(fd, EVIOCGABS(ABS_X), &in->abs_x);
    ioctl(fd, EVIOCGABS(ABS_Y), &in->abs_y);
    in->fd = fd;
    fprintf(stderr, "grabbed %s (%s)\n", name, path);
  }
  closedir(dir);
}

static void handle_ei(struct ei *ei) {
  ei_dispatch(ei);
  for (struct ei_event *event; (event = ei_get_event(ei)); ei_event_unref(event)) {
    struct ei_device *device = NULL;
    switch (ei_event_get_type(event)) {
    case EI_EVENT_SEAT_ADDED:
      ei_seat_bind_capabilities(ei_event_get_seat(event), EI_DEVICE_CAP_POINTER,
                                EI_DEVICE_CAP_POINTER_ABSOLUTE, EI_DEVICE_CAP_KEYBOARD,
                                EI_DEVICE_CAP_BUTTON, EI_DEVICE_CAP_SCROLL, NULL);
      break;
    case EI_EVENT_DEVICE_RESUMED:
      device = ei_event_get_device(event);
      if (ei_device_has_capability(device, EI_DEVICE_CAP_POINTER) && !pointer)
        pointer = ei_device_ref(device);
      if (ei_device_has_capability(device, EI_DEVICE_CAP_POINTER_ABSOLUTE) && !absolute)
        absolute = ei_device_ref(device);
      if (ei_device_has_capability(device, EI_DEVICE_CAP_KEYBOARD) && !keyboard)
        keyboard = ei_device_ref(device);
      if (ei_device_has_capability(device, EI_DEVICE_CAP_BUTTON) && !button)
        button = ei_device_ref(device);
      if (ei_device_has_capability(device, EI_DEVICE_CAP_SCROLL) && !scroll)
        scroll = ei_device_ref(device);
      ei_device_start_emulating(device, ++sequence);
      break;
    case EI_EVENT_DEVICE_PAUSED:
    case EI_EVENT_DEVICE_REMOVED:
      device = ei_event_get_device(event);
      if (device == pointer) pointer = ei_device_unref(pointer);
      if (device == absolute) absolute = ei_device_unref(absolute);
      if (device == keyboard) keyboard = ei_device_unref(keyboard);
      if (device == button) button = ei_device_unref(button);
      if (device == scroll) scroll = ei_device_unref(scroll);
      break;
    case EI_EVENT_DISCONNECT:
      fprintf(stderr, "KWin closed the EIS connection\n");
      exit(1);
    default:
      break;
    }
  }
}

static double scaled(const struct input_absinfo *abs, int value, uint32_t origin, uint32_t size) {
  int range = abs->maximum - abs->minimum;
  return range > 0 ? origin + (double)(value - abs->minimum) / range * size : origin;
}

static void frame_all(struct ei *ei) {
  uint64_t now = ei_now(ei);
  struct ei_device *devices[] = {pointer, absolute, keyboard, button, scroll};
  for (size_t i = 0; i < sizeof(devices) / sizeof(*devices); i++) {
    bool repeated = false;
    for (size_t j = 0; j < i; j++)
      repeated |= devices[j] == devices[i];
    if (devices[i] && !repeated)
      ei_device_frame(devices[i], now);
  }
}

static void handle_event(struct ei *ei, struct input *in, const struct input_event *ev) {
  if (ev->type == EV_KEY && ev->value != 2) {
    bool is_button = ev->code >= BTN_MOUSE && ev->code < BTN_JOYSTICK;
    if (is_button && button)
      ei_device_button_button(button, ev->code, ev->value);
    else if (!is_button && keyboard)
      ei_device_keyboard_key(keyboard, ev->code, ev->value);
  } else if (ev->type == EV_REL) {
    if (ev->code == REL_X && pointer)
      ei_device_pointer_motion(pointer, ev->value, 0);
    else if (ev->code == REL_Y && pointer)
      ei_device_pointer_motion(pointer, 0, ev->value);
    else if (ev->code == REL_WHEEL_HI_RES && scroll)
      ei_device_scroll_discrete(scroll, 0, -ev->value);
    else if (ev->code == REL_HWHEEL_HI_RES && scroll)
      ei_device_scroll_discrete(scroll, ev->value, 0);
    else if (ev->code == REL_WHEEL && scroll && !in->hires_wheel)
      ei_device_scroll_discrete(scroll, 0, -ev->value * 120);
    else if (ev->code == REL_HWHEEL && scroll && !in->hires_hwheel)
      ei_device_scroll_discrete(scroll, ev->value * 120, 0);
  } else if (ev->type == EV_ABS && absolute) {
    struct ei_region *region = ei_device_get_region(absolute, 0);
    if (region && ev->code == ABS_X)
      in->x = scaled(&in->abs_x, ev->value, ei_region_get_x(region), ei_region_get_width(region));
    if (region && ev->code == ABS_Y)
      in->y = scaled(&in->abs_y, ev->value, ei_region_get_y(region), ei_region_get_height(region));
    in->abs_pending = region != NULL;
  } else if (ev->type == EV_SYN && ev->code == SYN_REPORT) {
    if (in->abs_pending && absolute)
      ei_device_pointer_motion_absolute(absolute, in->x, in->y);
    in->abs_pending = false;
    frame_all(ei);
  }
}

int main(void) {
  sd_bus *bus = NULL;
  int fd = connect_eis(&bus);
  if (fd < 0)
    return 1;
  struct ei *ei = ei_new_sender(NULL);
  ei_configure_name(ei, "sunshine-headless-kwin-input");
  if (ei_setup_backend_fd(ei, fd) != 0) {
    fprintf(stderr, "ei_setup_backend_fd failed\n");
    return 1;
  }
  for (int i = 0; i < MAX_INPUTS; i++)
    inputs[i].fd = -1;
  for (;;) {
    struct pollfd fds[MAX_INPUTS + 1] = {{.fd = ei_get_fd(ei), .events = POLLIN}};
    bool missing = false;
    for (int i = 0; i < MAX_INPUTS; i++) {
      fds[i + 1] = (struct pollfd){.fd = inputs[i].fd, .events = POLLIN};
      missing |= inputs[i].fd < 0;
    }
    int ready = poll(fds, MAX_INPUTS + 1, missing ? 250 : -1);
    if (ready < 0 && errno != EINTR)
      return 1;
    if (missing)
      rescan();
    if (ready <= 0)
      continue;
    if (fds[0].revents)
      handle_ei(ei);
    for (int i = 0; i < MAX_INPUTS; i++) {
      if (!fds[i + 1].revents || inputs[i].fd < 0)
        continue;
      struct input_event events[64];
      ssize_t count = read(inputs[i].fd, events, sizeof(events));
      if (count < 0 && (errno == EAGAIN || errno == EINTR))
        continue;
      if (count <= 0) {
        close(inputs[i].fd);
        inputs[i].fd = -1;
        continue;
      }
      for (size_t e = 0; e < (size_t)count / sizeof(*events); e++)
        handle_event(ei, &inputs[i], &events[e]);
    }
  }
}
