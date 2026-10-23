
objc_library(
    name = "SSignalKit",
    enable_modules = True,
    module_name = "SSignalKit",
    srcs = glob([
        "Source/SSignalKit/*.m",
    ]),
    copts = [
        "-Werror",
        "-Wno-error=deprecated-declarations",
    ],
    hdrs = glob([
        "Source/SSignalKit/*.h",
    ]),
    includes = [
      "Source",
    ],
    deps = [
    ],
    sdk_frameworks = [
      "Foundation",
    ],
    visibility = [
        "//visibility:public",
    ],
)
