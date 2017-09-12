# rules_gogo_proto
bazel rules for generating go code with protoc and [gogoproto](https://github.com/gogo/protobuf)

Supports
* gogofast, gogofaster, and gogoslick code generators
* [gRPC](https://grpc.io/) code generation
* [gRPC-Gateway](https://github.com/grpc-ecosystem/grpc-gateway) code generation with swagger
* Swagger html docs

## Usage

In your workspace

```
git_repository(
    name = "com_github_tnarg_rules_gogo_proto",
    remote = "https://github.com/tnarg/rules_gogo_proto.git",
    commit = "9012b95628c7eb762e7dbd61be93f46ad20b9370", # or more recent git sha1
)

load("@com_github_tnarg_rules_gogo_proto//go_proto:rules.bzl", "gogo_repositories")

gogo_repositories()
```

Then in a directory containing one or more .proto files

```
load("@com_github_tnarg_rules_gogo_proto//go_proto:rules.bzl", "gogo_proto_library")

gogo_proto_library(
    name = "my_gogo_proto_lib",
    srcs = ["myservice.proto"],
    deps = [
         "@com_github_tnarg_rules_gogo_proto//google/api:go_default_library",      # annotations
         "@com_github_tnarg_rules_gogo_proto//google/protobuf:go_default_library", # timestamp
    ],
    with_grpc = True,
    with_gateway = True,
    with_swagger = True,
    visibility = ["//visibility:public"],
)
```

## Examples

See [rules_gogo_proto_examples](https://github.com/tnarg/rules_gogo_proto_examples) for more complete usage.
