/* Export RubyboyBrowser's Spinel entry points to JavaScript. */
#include <stdio.h>
#include "rubyboy.h"

#define EXPORT(name) __attribute__((export_name(name)))

enum entry { INIT, EXEC, READ_UPLOADED_ROM, READ_BUNDLED_ROM };
typedef struct { enum entry entry; const char *name; int direction, action; } call;
static char error[1024];

static void invoke(void *opaque) {
  call *c = opaque;
  switch (c->entry) {
  case INIT: sp_RubyboyBrowser_s_init(c->name); break;
  case EXEC: sp_RubyboyBrowser_s_exec(c->direction, c->action); break;
  case READ_UPLOADED_ROM: sp_RubyboyBrowser_s_read_rom_from_virtual_fs(); break;
  case READ_BUNDLED_ROM: sp_RubyboyBrowser_s_read_pre_installed_rom(c->name); break;
  }
}

/* Returns 0, or 1 with the Ruby exception in rubyboy_error(). */
static int run(call c) {
  const char *cls = NULL, *msg = NULL;
  if (!Init_rubyboy_browser_try(invoke, &c, &cls, &msg)) return 0;
  snprintf(error, sizeof error, "%s: %s", cls ? cls : "Error", msg ? msg : "");
  return 1;
}

EXPORT("rubyboy_init") int rubyboy_init(const char *rom_path) {
  static int initialized;
  if (!initialized) { Init_rubyboy_browser(); initialized = 1; }
  return run((call){INIT, rom_path});
}
EXPORT("rubyboy_exec") int rubyboy_exec(int direction, int action) {
  return run((call){EXEC, NULL, direction, action});
}
EXPORT("rubyboy_read_rom_from_virtual_fs") int rubyboy_read_rom_from_virtual_fs(void) {
  return run((call){READ_UPLOADED_ROM});
}
EXPORT("rubyboy_read_pre_installed_rom") int rubyboy_read_pre_installed_rom(const char *name) {
  return run((call){READ_BUNDLED_ROM, name});
}
EXPORT("rubyboy_error") const char *rubyboy_error(void) { return error; }
