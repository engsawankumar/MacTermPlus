#include "ccurl_shim.h"

CURLcode mtp_setopt_str(CURL *h, CURLoption opt, const char *value) { return curl_easy_setopt(h, opt, value); }
CURLcode mtp_setopt_long(CURL *h, CURLoption opt, long value) { return curl_easy_setopt(h, opt, value); }
CURLcode mtp_setopt_off(CURL *h, CURLoption opt, curl_off_t value) { return curl_easy_setopt(h, opt, value); }
CURLcode mtp_setopt_ptr(CURL *h, CURLoption opt, void *value) { return curl_easy_setopt(h, opt, value); }
CURLcode mtp_setopt_slist(CURL *h, CURLoption opt, struct curl_slist *list) { return curl_easy_setopt(h, opt, list); }

CURLcode mtp_setopt_writefn(CURL *h, mtp_data_cb fn, void *userdata) {
    CURLcode rc = curl_easy_setopt(h, CURLOPT_WRITEFUNCTION, fn);
    if (rc != CURLE_OK) return rc;
    return curl_easy_setopt(h, CURLOPT_WRITEDATA, userdata);
}

CURLcode mtp_setopt_readfn(CURL *h, mtp_data_cb fn, void *userdata) {
    CURLcode rc = curl_easy_setopt(h, CURLOPT_READFUNCTION, fn);
    if (rc != CURLE_OK) return rc;
    return curl_easy_setopt(h, CURLOPT_READDATA, userdata);
}

CURLcode mtp_setopt_progressfn(CURL *h, mtp_progress_cb fn, void *userdata) {
    CURLcode rc = curl_easy_setopt(h, CURLOPT_XFERINFOFUNCTION, fn);
    if (rc != CURLE_OK) return rc;
    rc = curl_easy_setopt(h, CURLOPT_XFERINFODATA, userdata);
    if (rc != CURLE_OK) return rc;
    return curl_easy_setopt(h, CURLOPT_NOPROGRESS, 0L);
}

CURLcode mtp_getinfo_str(CURL *h, CURLINFO info, const char **out) { return curl_easy_getinfo(h, info, out); }
CURLcode mtp_getinfo_long(CURL *h, CURLINFO info, long *out) { return curl_easy_getinfo(h, info, out); }
