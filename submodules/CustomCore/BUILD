load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "CustomCore",
    module_name = "CustomCore",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [],
    deps = [
        "//submodules/BuildConfig:BuildConfig",
    ],
    visibility = ["//visibility:public"],
)
