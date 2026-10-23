
objc_library(
    name = "libphonenumber",
    enable_modules = True,
    module_name = "libphonenumber",
    srcs = glob([
        "Sources/*.m",
        "Sources/*.h",
    ]),
    hdrs = glob([
        "PublicHeaders/**/*.h",
    ]),
    includes = [
        "PublicHeaders",
    ],
    sdk_frameworks = [
      "Foundation",
    ],
    copts = [
        "-Werror",
        "-Wno-error=deprecated-declarations",
    ],
    visibility = [
        "//visibility:public",
    ],
)
