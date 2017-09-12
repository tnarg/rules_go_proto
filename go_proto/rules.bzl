load("@io_bazel_rules_go//go:def.bzl", "go_repository", "go_library")

_common_attrs = {
    "srcs": attr.label_list(
        mandatory = True,
        allow_files = True,
    ),
    "deps": attr.label_list(),
    "protoc": attr.label(
        default = Label("@com_github_google_protobuf//:protoc"),
        executable = True,
        single_file = True,
        allow_files = True,
        cfg = "host",
    ),
    "well_known_protos": attr.label(
        default = Label("@com_github_google_protobuf//:well_known_protos")
    ),
    "well_known_gogoprotos": attr.label(
        default = Label("//:gogoproto/gogo.proto"),
        allow_files = True,
    ),
    "outs": attr.output_list(mandatory = True),
}

WELL_KNOWN_DEPS = [
    "@com_github_gogo_protobuf//gogoproto:go_default_library",
    "@com_github_gogo_protobuf//proto:go_default_library",
    "@com_github_gogo_protobuf//types:go_default_library",
    "@com_github_golang_protobuf//proto:go_default_library",
    "@com_github_golang_protobuf//ptypes/any:go_default_library",
    "@com_github_golang_protobuf//ptypes/duration:go_default_library",
    "@com_github_golang_protobuf//ptypes/empty:go_default_library",
    "@com_github_golang_protobuf//ptypes/struct:go_default_library",
    "@com_github_golang_protobuf//ptypes/timestamp:go_default_library",
    "@com_github_golang_protobuf//ptypes/wrappers:go_default_library",
]

WELL_KNOWN_M_IMPORTS = [
    "Mgogoproto/gogo.proto=github.com/gogo/protobuf/gogoproto",
    "Mgoogle/protobuf/any.proto=github.com/golang/protobuf/ptypes/any",
    "Mgoogle/protobuf/duration.proto=github.com/golang/protobuf/ptypes/duration",
    "Mgoogle/protobuf/empty.proto=github.com/golang/protobuf/ptypes/empty",
    "Mgoogle/protobuf/struct.proto=github.com/golang/protobuf/ptypes/struct",
    "Mgoogle/protobuf/timestamp.proto=github.com/golang/protobuf/ptypes/timestamp",
    "Mgoogle/protobuf/wrappers.proto=github.com/golang/protobuf/ptypes/wrappers",
]

def _safe_proto_path(proto_path):
    if proto_path == "":
        return "."
    else:
        return proto_path

def _proto_gen_impl(ctx):
    plugins = "plugins=grpc," if ctx.attr.with_grpc else ""

    proto_paths = dict()
    proto_paths[_safe_proto_path(ctx.label.workspace_root)] = None
    proto_paths[_safe_proto_path(ctx.attr.well_known_protos.label.workspace_root) + "/src"] = None
    proto_paths[_safe_proto_path(ctx.attr.well_known_gogoprotos.label.workspace_root)] = None

    m_imports = []
    dep_protos = []
    for dep in ctx.attr.deps:
        dep_protos += dep.protos
        m_imports += dep.m_exports
        proto_paths[_safe_proto_path(dep.label.workspace_root)] = None

    proto_path_args = []
    for proto_path in proto_paths:
        proto_path_args += ["-I" + proto_path]

    inputs = (ctx.files.srcs +
              dep_protos +
              [ctx.executable.protoc] +
              ctx.files.protoc_gen_gogofast +
              ctx.files.protoc_gen_gogofaster +
              ctx.files.protoc_gen_gogoslick +
              ctx.files.well_known_protos +
              ctx.files.well_known_gogoprotos)

    m_exports = []
    outputs = []
    rename_cmds = []
    for src in ctx.files.srcs:
        fname = src.basename[:-len(".proto")] + ".pb.go"
        out = ctx.new_file(ctx.genfiles_dir, fname)
        outputs += [out]

        if ctx.attr.importpath:
            rename_cmds += ["mv %s/%s/%s %s" % (ctx.genfiles_dir.path, ctx.attr.importpath, fname, out.path)]
            m_exports += ["M%s=%s" % (src.path, ctx.attr.importpath)]
        else:
            m_exports += ["M%s=%s/%s" % (src.path, ctx.attr.go_prefix.go_prefix, src.dirname)]

    protoc_cmd = " ".join([
        ctx.executable.protoc.path,
        "--gogofast_out=%s%s:%s" % (plugins, ",".join(WELL_KNOWN_M_IMPORTS + m_imports), ctx.genfiles_dir.path,),
    ] + proto_path_args + [src.path for src in ctx.files.srcs])

    cmd = protoc_cmd + ";" + ";".join(rename_cmds)
    ctx.action(
        inputs = inputs,
        outputs = outputs,
        command = cmd,
        env = {
            "PATH": ":".join([
                ctx.files.protoc_gen_gogofast[0].dirname,
                ctx.files.protoc_gen_gogofaster[0].dirname,
                ctx.files.protoc_gen_gogoslick[0].dirname,
                "/bin",
            ])
        },
    )

    return struct(
        protos = ctx.files.srcs + dep_protos,
        m_exports = m_imports + m_exports,
    )

_proto_gen = rule(
    attrs = _common_attrs + {
        "protoc_gen_gogofast": attr.label(
            default = Label("@com_github_gogo_protobuf//protoc-gen-gogofast"),
            allow_files = True,
            cfg = "host",
        ),
        "protoc_gen_gogofaster": attr.label(
            default = Label("@com_github_gogo_protobuf//protoc-gen-gogofaster"),
            allow_files = True,
            cfg = "host",
        ),
        "protoc_gen_gogoslick": attr.label(
            default = Label("@com_github_gogo_protobuf//protoc-gen-gogoslick"),
            allow_files = True,
            cfg = "host",
        ),
        "with_grpc": attr.bool(
            default = False,
            mandatory = True,
        ),
        "go_prefix": attr.label(
            providers = ["go_prefix"],
            default = Label(
                "//:go_prefix",
                relative_to_caller_repository = True,
            ),
            allow_files = False,
            cfg = "host",
        ),
        "importpath": attr.string(),
    },
    output_to_genfiles = True,
    implementation = _proto_gen_impl,
)

def _grpc_gateway_gen_impl(ctx):
    proto_paths = dict()
    proto_paths[_safe_proto_path(ctx.label.workspace_root)] = None
    proto_paths[_safe_proto_path(ctx.attr.well_known_protos.label.workspace_root) + "/src"] = None
    proto_paths[_safe_proto_path(ctx.attr.well_known_gogoprotos.label.workspace_root)] = None

    m_imports = []
    dep_protos = []
    for dep in ctx.attr.deps:
        dep_protos += dep.protos
        m_imports += dep.m_exports
        proto_paths[_safe_proto_path(dep.label.workspace_root)] = None

    proto_path_args = []
    for proto_path in proto_paths:
        proto_path_args += ["-I" + proto_path]

    inputs = (ctx.files.srcs +
              dep_protos +
              [ctx.executable.protoc] +
              ctx.files.protoc_gen_grpc_gateway +
              ctx.files.well_known_protos +
              ctx.files.well_known_gogoprotos)

    outputs = []
    for src in ctx.files.srcs:
        fname = src.basename[:-len(".proto")] + ".pb.gw.go"
        out = ctx.new_file(ctx.genfiles_dir, fname)
        outputs += [out]

    cmd = " ".join([
        ctx.executable.protoc.path,
        "--grpc-gateway_out=%s:%s" % (",".join(WELL_KNOWN_M_IMPORTS + m_imports), ctx.genfiles_dir.path,),
    ] + proto_path_args + [src.path for src in ctx.files.srcs])

    ctx.action(
        inputs = inputs,
        outputs = outputs,
        command = cmd,
        env = {
            "PATH": ctx.files.protoc_gen_grpc_gateway[0].dirname + ":/bin",
        },
    )

_grpc_gateway_gen = rule(
    attrs = _common_attrs + {
        "protoc_gen_grpc_gateway": attr.label(
            default = Label("@com_github_grpc_ecosystem_grpc_gateway//protoc-gen-grpc-gateway"),
            allow_files = True,
            cfg = "host",
        ),
    },
    output_to_genfiles = True,
    implementation = _grpc_gateway_gen_impl,
)

def _swagger_gen_impl(ctx):
    proto_paths = dict()
    proto_paths[_safe_proto_path(ctx.label.workspace_root)] = None
    proto_paths[_safe_proto_path(ctx.attr.well_known_protos.label.workspace_root) + "/src"] = None
    proto_paths[_safe_proto_path(ctx.attr.well_known_gogoprotos.label.workspace_root)] = None

    m_imports = []
    dep_protos = []
    for dep in ctx.attr.deps:
        dep_protos += dep.protos
        m_imports += dep.m_exports
        proto_paths[_safe_proto_path(dep.label.workspace_root)] = None

    proto_path_args = []
    for proto_path in proto_paths:
        proto_path_args += ["-I" + proto_path]

    inputs = (ctx.files.srcs +
              dep_protos +
              [ctx.executable.protoc] +
              ctx.files.protoc_gen_swagger +
              ctx.files.well_known_protos +
              ctx.files.well_known_gogoprotos)

    outputs = []
    for src in ctx.files.srcs:
        fname = src.basename[:-len(".proto")] + ".swagger.json"
        out = ctx.new_file(ctx.genfiles_dir, fname)
        outputs += [out]

    cmd = " ".join([
        ctx.executable.protoc.path,
        "--swagger_out=%s:%s" % (",".join(WELL_KNOWN_M_IMPORTS + m_imports), ctx.genfiles_dir.path,),
    ] + proto_path_args + [src.path for src in ctx.files.srcs])

    ctx.action(
        inputs = inputs,
        outputs = outputs,
        command = cmd,
        env = {
            "PATH": ctx.files.protoc_gen_swagger[0].dirname + ":/bin",
        },
    )

_swagger_gen = rule(
    attrs = _common_attrs + {
        "protoc_gen_swagger": attr.label(
            default = Label("@com_github_grpc_ecosystem_grpc_gateway//protoc-gen-swagger"),
            allow_files = True,
            cfg = "host",
        ),
    },
    output_to_genfiles = True,
    implementation = _swagger_gen_impl,
)

def _bindata_impl(ctx):

    index_entries = []
    redoc_pages = []
    for src in ctx.files.srcs:
        fname = src.basename[:-len(".json")] + ".html"
        redoc_page = ctx.new_file(src, fname)
        redoc_pages += [redoc_page]
        ctx.template_action(
            template=ctx.file.redoc_template,
            output=redoc_page,
            substitutions={
                "{SWAGGER_JSON}": src.basename,
            },
        )
        index_entries += ["<li><a href=\"%s\">%s</a></li>" % (redoc_page.basename, src.basename[:-len(".swagger.json")])]

    index = ctx.new_file("index.html")
    ctx.template_action(
        template=ctx.file.redoc_index_template,
        output=index,
        substitutions={
            "{INDEX_ENTRIES}": "\n".join(index_entries),
        },
    )

    if ctx.attr.package:
        pkg = ctx.attr.package
    else:
        pkg = "_".join(ctx.label.package.split("/"))

    inputs = ctx.files.srcs + redoc_pages + [index, ctx.executable.bindata]
    ctx.action(
        inputs = inputs,
        outputs = [ctx.outputs.bindata],
        command = "%s -pkg %s -prefix %s -o %s %s" % (
            ctx.executable.bindata.path,
            pkg,
            "%s/%s" % (ctx.genfiles_dir.path, ctx.label.package),
            ctx.outputs.bindata.path,
            " ".join([src.path for src in (ctx.files.srcs + redoc_pages + [index])]),
        ),
    )

_bindata_gen = rule(
    attrs = {
        "srcs": attr.label_list(
            mandatory = True,
            allow_files = True,
        ),
        "bindata": attr.label(
            default = Label("@com_github_jteeuwen_go_bindata//go-bindata"),
            executable = True,
            single_file = True,
            allow_files = True,
            cfg = "host",
        ),
        "redoc_template": attr.label(
            default = Label("//go_proto:redoc.tpl"),
            allow_files=True,
            single_file=True,
        ),
        "redoc_index_template": attr.label(
            default = Label("//go_proto:index.tpl"),
            allow_files=True,
            single_file=True,
        ),
        "package": attr.string(),
    },
    output_to_genfiles = True,
    outputs = {
        "bindata": "%{name}.go"
    },
    implementation = _bindata_impl,
)

def go_proto_library(
        name,
        srcs = None,
        importpath = None,
        package = None,
        deps = None,
        pure_go_deps = None,
        visibility = None,
        with_grpc = False,
        with_gateway = False,
        with_swagger = False):
    if not name:
        fail("name is required", "name")
    if not srcs:
        fail("srcs required", "srcs")
    if not deps:
        deps = []

    if not pure_go_deps:
        pure_go_deps = []

    proto_deps = [dep + "_proto" for dep in deps]

    #TODO(gmonroe): support labels in srcs
    proto_outs = [s[:-len(".proto")] + ".pb.go"
                  for s in srcs]

    proto_name = name + "_proto"
    _proto_gen(
        name = proto_name,
        srcs = srcs,
        deps = proto_deps,
        importpath = importpath,
        outs = proto_outs,
        with_grpc = with_grpc or with_gateway,
        visibility = visibility,
    )

    lib_srcs = [":" + proto_name]

    full_deps = deps + pure_go_deps + WELL_KNOWN_DEPS

    if with_grpc or with_gateway:
        full_deps += [
            # grpc
            "@org_golang_google_grpc//:go_default_library",
            "@org_golang_google_grpc//codes:go_default_library",
            "@org_golang_google_grpc//grpclog:go_default_library",
            "@org_golang_google_grpc//status:go_default_library",

            # /x/net
            "@org_golang_x_net//context:go_default_library",
        ]

    if with_gateway:
        full_deps += [
            # grpc gateway
            "@com_github_grpc_ecosystem_grpc_gateway//runtime:go_default_library",
            "@com_github_grpc_ecosystem_grpc_gateway//utilities:go_default_library",
        ]

        grpc_gateway_outs = [s[:-len(".proto")] + ".pb.gw.go"
              for s in srcs]

        grpc_gateway_name = name + "_grpc_gateway"
        _grpc_gateway_gen(
            name = grpc_gateway_name,
            srcs = srcs,
            deps = proto_deps,
            #importpath = importpath,
            outs = grpc_gateway_outs,
        )

        lib_srcs += [":" + grpc_gateway_name]

    if with_swagger:
        swagger_outs = [s[:-len(".proto")] + ".swagger.json"
              for s in srcs]

        swagger_name = name + "_swagger_json"
        _swagger_gen(
            name = swagger_name,
            srcs = srcs,
            deps = proto_deps,
            #importpath = importpath,
            outs = swagger_outs,
        )

        bindata_outs = [s[:-len(".proto")] + ".swagger.go"
              for s in srcs]
        bindata_name = name + "_swagger_bindata"
        _bindata_gen(
            name = bindata_name,
            srcs = [":" + swagger_name],
            package = package,
        )
        lib_srcs += [":" + bindata_name]

    go_library(
        name = name,
        srcs = lib_srcs,
        deps = full_deps,
        importpath = importpath,
        visibility = visibility,
    )

_go_grpc_repositories = {
    "github.com/golang/glog":                 "23def4e6c14b4da8ac2ed8007337bc5eb5007998",
    "github.com/golang/protobuf":             "83cd65fc365ace80eb6b6ecfc45203e43edfbc70",
    "github.com/gogo/protobuf":               "2adc21fd136931e0388e278825291678e1d98309",
    "github.com/google/protobuf":             "6699f2cf64c656d96f4d6f93fa9563faf02e94b4",
    "github.com/grpc-ecosystem/grpc-gateway": "f2862b476edcef83412c7af8687c9cd8e4097c0f",
    "github.com/jteeuwen/go-bindata":         "a0ff2567cfb70903282db057e799fd826784d41d",
    "golang.org/x/net":                       "5961165da77ad3a2abf3a77ea904c13a76b0b073",
    "golang.org/x/text":                      "e113a52b01bdd1744681b6ce70c2e3d26b58d389",
    "google.golang.org/genproto":             "411e09b969b1170a9f0c467558eb4c4c110d9c77",
    "google.golang.org/grpc":                 "7db1564ba1229bc42919bb1f6d9c4186f3aa8678",
}

def go_grpc_repositories():
    for importpath, commit in _go_grpc_repositories.items():
        _maybe_go_repository(importpath, commit)

def _go_repository_name(importpath):
    a, b = importpath.split('/', 1)
    host_parts = a.split('.')

    result = []
    for i in range(len(host_parts)):
        result.append(host_parts.pop())

    result.append(b.replace('-', '_').replace('/', '_').replace('.', '_'))

    return "_".join(result)

def _maybe_go_repository(importpath, commit):
    name = _go_repository_name(importpath)
    if name not in native.existing_rules():
        go_repository(
            name=name,
            importpath=importpath,
            commit=commit,
        )
