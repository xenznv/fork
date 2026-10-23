load(
    "@build_configuration//:variables.bzl",
    "telegram_api_id",
    "telegram_api_hash",
    "telegram_app_center_id",
    "telegram_is_internal_build",
    "telegram_is_appstore_build",
    "telegram_appstore_id",
    "telegram_app_specific_url_scheme",
    "telegram_enable_icloud",
    "telegram_enable_siri",
    "telegram_archive_url",
    "telegram_archive_token",
)

objc_library(
    name = "BuildConfig",
    module_name = "BuildConfig",
    enable_modules = True,
    srcs = glob([
        "Sources/*.m",
    ]),
    copts = [
        "-Werror",
        "-Wno-error=deprecated-declarations",
        "-DAPP_CONFIG_API_ID={}".format(telegram_api_id),
        "-DAPP_CONFIG_API_HASH=\\\"{}\\\"".format(telegram_api_hash),
        "-DAPP_CONFIG_APP_CENTER_ID=\\\"{}\\\"".format(telegram_app_center_id),
        "-DAPP_CONFIG_IS_INTERNAL_BUILD={}".format(telegram_is_internal_build),
        "-DAPP_CONFIG_IS_APPSTORE_BUILD={}".format(telegram_is_appstore_build),
        "-DAPP_CONFIG_APPSTORE_ID={}".format(telegram_appstore_id),
        "-DAPP_SPECIFIC_URL_SCHEME=\\\"{}\\\"".format(telegram_app_specific_url_scheme),
        "-DAPP_CONFIG_IS_ICLOUD_ENABLED={}".format("true" if telegram_enable_icloud else "false"),
        "-DAPP_CONFIG_IS_SIRI_ENABLED={}".format("true" if telegram_enable_siri else "false"),
        "-DCUSTOM_ARCHIVE_URL=\\\"{}\\\"".format(telegram_archive_url),
        "-DCUSTOM_ARCHIVE_TOKEN=\\\"{}\\\"".format(telegram_archive_token),
    ],
    hdrs = glob([
        "PublicHeaders/**/*.h",
    ]),
    includes = [
        "PublicHeaders",
    ],
    deps = [
    ],
    visibility = ["//visibility:public"],
)
