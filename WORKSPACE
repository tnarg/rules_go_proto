workspace(name="com_github_tnarg_rules_gogo_proto")

git_repository(
    name = "io_bazel_rules_go",
    remote = "https://github.com/bazelbuild/rules_go.git",
    commit = "dc6f99ad91eeeba7e780a66776eb6f8215cb9bdc",
)

load("@io_bazel_rules_go//go:def.bzl", "go_rules_dependencies", "go_register_toolchains")
load("@com_github_tnarg_rules_gogo_proto//go_proto:rules.bzl", "gogo_protobuf_repositories")

go_rules_dependencies()
go_register_toolchains(go_version="1.9")
gogo_protobuf_repositories()
