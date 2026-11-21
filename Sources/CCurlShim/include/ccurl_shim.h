#ifndef CCURL_SHIM_H
#define CCURL_SHIM_H
#include <curl/curl.h>

/* Thin, non-variadic wrappers so Swift can configure libcurl (curl_easy_setopt is variadic). */
typedef size_t (*mtp_data_cb)(char *ptr, size_t size, size_t nmemb, void *userdata);
typedef int (*mtp_progress_cb)(void *userdata, curl_off_t dltotal, curl_off_t dlnow, curl_off_t ultotal, curl_off_t ulnow);

CURLcode mtp_setopt_str(CURL *h, CURLoption opt, const char *value);
CURLcode mtp_setopt_long(CURL *h, CURLoption opt, long value);
CURLcode mtp_setopt_off(CURL *h, CURLoption opt, curl_off_t value);
CURLcode mtp_setopt_ptr(CURL *h, CURLoption opt, void *value);
CURLcode mtp_setopt_slist(CURL *h, CURLoption opt, struct curl_slist *list);
CURLcode mtp_setopt_writefn(CURL *h, mtp_data_cb fn, void *userdata);
CURLcode mtp_setopt_readfn(CURL *h, mtp_data_cb fn, void *userdata);
CURLcode mtp_setopt_progressfn(CURL *h, mtp_progress_cb fn, void *userdata);
CURLcode mtp_getinfo_str(CURL *h, CURLINFO info, const char **out);
CURLcode mtp_getinfo_long(CURL *h, CURLINFO info, long *out);
#endif
