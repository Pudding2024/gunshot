#include <assert.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include "libgotohp.h"
int main(void) {
    assert(GunshotPing() == 1);
    GunshotSetHostBearerProvider(0);
    char *response = GunshotRequest("{\"op\":\"ping\"}", "settings");
    assert(strstr(response, "not_initialized") != 0);
    GunshotFree(response);
    char directory[] = ".build/bridge-state-XXXXXX";
    assert(mkdtemp(directory) != NULL);
    assert(GunshotInitialize(directory) == 0);
    // Reproduce the Objective-C integer-boxing failure at the actual Go decoder.
    response = GunshotRequest("{\"op\":\"conditions\",\"online\":1,\"wifi\":true,\"charging\":0}",
                              "daemon");
    assert(strstr(response, "\"ok\":false") != NULL);
    GunshotFree(response);
    response = GunshotRequest(
        "{\"op\":\"conditions\",\"online\":true,\"wifi\":true,\"charging\":false}", "daemon");
    assert(strstr(response, "\"ok\":true") != NULL);
    GunshotFree(response);
    response = GunshotRequest("{\"op\":\"list\"}", "settings");
    assert(strstr(response, "\"online\":true") != NULL);
    assert(strstr(response, "\"wifi\":true") != NULL);
    assert(strstr(response, "\"charging\":false") != NULL);
    GunshotFree(response);
    puts("PASS real Go bridge rejects numeric conditions and applies JSON booleans");
    return 0;
}
