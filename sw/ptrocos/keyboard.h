#ifndef PTROCOS_KEYBOARD_H
#define PTROCOS_KEYBOARD_H
#include <stdint.h>
enum ptrocos_key {
    KEY_UP=0x100, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_HOME, KEY_END,
    KEY_DELETE, KEY_INSERT, KEY_PAGE_UP, KEY_PAGE_DOWN
};
struct ptrocos_keyboard {
    uint8_t extended, release, pause_bytes;
    uint8_t left_shift, right_shift, left_ctrl, right_ctrl, caps, caps_down;
};
void ptrocos_keyboard_reset(struct ptrocos_keyboard *state);
// Returns ASCII / KEY_* on key-down, or -1 for prefixes, key-up and unknown keys.
int ptrocos_keyboard_decode(struct ptrocos_keyboard *state, uint8_t scan);
#endif
