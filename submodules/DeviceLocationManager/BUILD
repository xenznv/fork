load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "DeviceLocationManager",
    module_name = "DeviceLocationManager",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/CustomCore:CustomCore",
    ],
    visibility = [
        "//visibility:public",
    ],
)
