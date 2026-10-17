load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

models = glob([
    "Models/*.fbs",
])

model_names = [
    f[7:-4] for f in models
]

generated_models = [ "{}_generated.swift".format(name) for name in model_names ]
flatc_input = " ".join([ "$(location Models/{}.fbs)".format(name) for name in model_names ])

genrule(
    name = "GenerateModels",
    srcs = models,
    tools = [
        "//third-party/flatc:flatc_bin"
    ],
    cmd_bash = 
    """
    set -eux
    FLATC_RELATIVE="$(location //third-party/flatc:flatc_bin)"
    echo "FLATC_RELATIVE=$FLATC_RELATIVE"

    # The location is relative to execroot. The genrule runs with cwd at execroot,
    # so FLATC is just the relative path.
    FLATC="$FLATC_RELATIVE"
    echo "FLATC=$FLATC"
    FLATC_ABS="$(pwd)/$FLATC"
    echo "FLATC_ABS=$FLATC_ABS"
    ls -la "$FLATC_ABS" || echo "FLATC NOT FOUND at $FLATC_ABS"
    file "$FLATC_ABS" || true
    echo "cwd=$(pwd)"
    echo "RULEDIR=$RULEDIR"
    echo "pwd_output=$(pwd)"

    BUILD_DIR="$(RULEDIR)/build"
    rm -rf "$$BUILD_DIR"
    mkdir -p "$$BUILD_DIR"

    "$FLATC" --require-explicit-ids --swift -I "$(RULEDIR)/Models" -o "$BUILD_DIR" {flatc_input}
    """.format(
        flatc_input=flatc_input
    ) + "\n" + "\n".join([
    """
    cp "$BUILD_DIR/{name}_generated.swift" "$(location {name}_generated.swift)"
    """.format(name=name) for name in model_names
    ]),
    outs = generated_models,
    visibility = [
        "//visibility:public",
    ]
)

swift_library(
    name = "FlatSerialization",
    module_name = "FlatSerialization",
    srcs = generated_models,
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/TelegramCore/FlatBuffers",
    ],
    visibility = [
        "//visibility:public",
    ],
)
