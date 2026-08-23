#include <rime_api.h>

#include <cstdio>
#include <cstring>
#include <string>

namespace {

int fail(const char* message) {
  std::fprintf(stderr, "Rime smoke failed: %s\n", message);
  return 1;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc != 5) {
    std::fprintf(stderr,
                 "Usage: %s <user-data-dir> <shared-data-dir> <input> "
                 "<expected-candidate>\n",
                 argv[0]);
    return 2;
  }

  const char* user_data_dir = argv[1];
  const char* shared_data_dir = argv[2];
  const char* input = argv[3];
  const char* expected = argv[4];
  RimeApi* api = rime_get_api();
  if (!api) return fail("rime_get_api returned null");

  RIME_STRUCT(RimeTraits, traits);
  traits.shared_data_dir = shared_data_dir;
  traits.user_data_dir = user_data_dir;
  traits.distribution_name = "Rime Smart Simplified smoke";
  traits.distribution_code_name = "rime-smart-simplified-smoke";
  traits.distribution_version = "1";
  traits.app_name = "rime.rime-smart-simplified-smoke";
  traits.min_log_level = 2;
  traits.log_dir = user_data_dir;

  api->setup(&traits);
  api->initialize(&traits);

  int result = 1;
  RimeSessionId session = api->create_session();
  if (!session) {
    result = fail("could not create a librime session");
    api->finalize();
    return result;
  }

  if (!api->select_schema(session, "rime_ice")) {
    result = fail("could not select rime_ice");
  } else if (!api->set_input(session, input)) {
    result = fail("could not set input");
  } else {
    RIME_STRUCT(RimeContext, context);
    if (!api->get_context(session, &context)) {
      result = fail("could not read candidate context");
    } else {
      bool found = false;
      std::printf("input=%s candidates=", input);
      for (int index = 0; index < context.menu.num_candidates; ++index) {
        const char* text = context.menu.candidates[index].text;
        if (index) std::printf("|");
        std::printf("%s", text ? text : "");
        if (text && std::strcmp(text, expected) == 0) found = true;
      }
      std::printf("\n");
      api->free_context(&context);
      result = found ? 0 : fail("expected candidate was not on the first page");
    }
  }

  api->destroy_session(session);
  api->finalize();
  return result;
}
