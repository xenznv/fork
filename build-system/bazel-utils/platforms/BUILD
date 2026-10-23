# Target platforms for building library targets directly (fast CI checks).
#
# `Telegram/Telegram` is an ios_application, so bazel applies the apple
# configuration transition to its whole dependency graph. Building a bare
# swift_library target has no transition and compiles for the host (macOS),
# which fails with "no such module 'UIKit'". Passing
# `--platforms=//build-system/bazel-utils/platforms:ios_arm64_device` puts
# the requested targets on the ios_arm64 toolchain without wrapping them
# in an application.

platform(
    name = "ios_arm64_device",
    constraint_values = [
        "@platforms//os:ios",
        "@platforms//cpu:arm64",
        "@build_bazel_apple_support//constraints:device",
    ],
)

platform(
    name = "ios_sim_arm64",
    constraint_values = [
        "@platforms//os:ios",
        "@platforms//cpu:arm64",
        "@build_bazel_apple_support//constraints:simulator",
    ],
)
