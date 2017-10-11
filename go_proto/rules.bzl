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
    "gogo_protos": attr.label(
        default = Label("//:gogoproto/gogo.proto"),
        allow_files = True,
    ),
    "govalidator_protos": attr.label(
        default = Label("//:github.com/mwitkow/go-proto-validators/validator.proto"),
        allow_files = True,
    ),
    "outs": attr.output_list(mandatory = True),
}

WELL_KNOWN_DEPS = [
    "@com_github_mwitkow_go_proto_validators//:go_default_library",
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
    proto_paths = dict()
    proto_paths[_safe_proto_path(ctx.label.workspace_root)] = None
    proto_paths[_safe_proto_path(ctx.attr.well_known_protos.label.workspace_root) + "/src"] = None
    proto_paths[_safe_proto_path(ctx.attr.gogo_protos.label.workspace_root)] = None
    proto_paths[_safe_proto_path(ctx.attr.govalidator_protos.label.workspace_root)] = None

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
              ctx.files.protoc_gen_go +
              ctx.files.protoc_gen_gogofast +
              ctx.files.protoc_gen_gogofaster +
              ctx.files.protoc_gen_gogoslick +
              ctx.files.protoc_gen_govalidators +
              ctx.files.protoc_gen_letmegrpc +
              ctx.files.well_known_protos +
              ctx.files.gogo_protos +
              ctx.files.govalidator_protos)

    m_exports = []
    outputs = []
    rename_cmds = []
    for src in ctx.files.srcs:
        fname = src.basename[:-len(".proto")] + ".pb.go"
        out = ctx.new_file(ctx.genfiles_dir, fname)
        outputs += [out]

        validator_fname = ""
        validator_out = None
        if ctx.attr.with_validators:
            validator_fname = src.basename[:-len(".proto")] + ".validator.pb.go"
            validator_out = ctx.new_file(ctx.genfiles_dir, validator_fname)
            outputs += [validator_out]

        letmegrpc_fname = ""
        letmegrpc_out = None
        if ctx.attr.with_rpc_forms:
            letmegrpc_fname = src.basename[:-len(".proto")] + ".letmegrpc.go"
            letmegrpc_out = ctx.new_file(ctx.genfiles_dir, letmegrpc_fname)
            outputs += [letmegrpc_out]

        if ctx.attr.importpath:
            rename_cmds += ["mv %s/%s/%s %s" % (ctx.genfiles_dir.path, ctx.attr.importpath, fname, out.path)]
            if ctx.attr.with_validators:
                rename_cmds += ["mv %s/%s/%s %s" % (ctx.genfiles_dir.path, ctx.attr.importpath, validator_fname, validator_out.path)]
            if ctx.attr.with_rpc_forms:
                rename_cmds += ["mv %s/%s/%s %s" % (ctx.genfiles_dir.path, ctx.attr.importpath, letmegrpc_fname, letmegrpc_out.path)]

            m_exports += ["M%s=%s" % (src.path, ctx.attr.importpath)]
        else:
            m_exports += ["M%s=%s/%s" % (src.path, ctx.attr.go_prefix.go_prefix, src.dirname)]

    plugins = "plugins=grpc," if ctx.attr.with_grpc else ""
    full_m_imports = ",".join(WELL_KNOWN_M_IMPORTS + m_imports)
    validators = "--govalidators_out=%s:%s" % (full_m_imports, ctx.genfiles_dir.path,) if ctx.attr.with_validators else ""
    letmegrpc = "--letmegrpc_out=%s:%s" % (full_m_imports, ctx.genfiles_dir.path,) if ctx.attr.with_rpc_forms else ""

    generator = "gogo%s" % (ctx.attr.mode,) if ctx.attr.mode else "go"
    protoc_cmd = " ".join([
        ctx.executable.protoc.path,
        "--%s_out=%s%s:%s" % (generator, plugins, full_m_imports, ctx.genfiles_dir.path,),
        validators,
        letmegrpc,
    ] + proto_path_args + [src.path for src in ctx.files.srcs])

    cmd = protoc_cmd + ";" + ";".join(rename_cmds)
    ctx.action(
        inputs = inputs,
        outputs = outputs,
        command = cmd,
        env = {
            "PATH": ":".join([
                ctx.files.protoc_gen_go[0].dirname,
                ctx.files.protoc_gen_gogofast[0].dirname,
                ctx.files.protoc_gen_gogofaster[0].dirname,
                ctx.files.protoc_gen_gogoslick[0].dirname,
                ctx.files.protoc_gen_govalidators[0].dirname,
                ctx.files.protoc_gen_letmegrpc[0].dirname,
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
        "mode": attr.string(
            mandatory = False,
        ),
        "protoc_gen_go": attr.label(
            default = Label("@com_github_golang_protobuf//protoc-gen-go"),
            allow_files = True,
            cfg = "host",
        ),
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
        "protoc_gen_govalidators": attr.label(
            default = Label("@com_github_mwitkow_go_proto_validators//protoc-gen-govalidators"),
            allow_files = True,
            cfg = "host",
        ),
        "protoc_gen_letmegrpc": attr.label(
            default = Label("@com_github_gogo_letmegrpc//protoc-gen-letmegrpc"),
            allow_files = True,
            cfg = "host",
        ),
        "with_grpc": attr.bool(
            default = False,
            mandatory = True,
        ),
        "with_validators": attr.bool(
            default = False,
            mandatory = True,
        ),
        "with_rpc_forms": attr.bool(
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
    proto_paths[_safe_proto_path(ctx.attr.gogo_protos.label.workspace_root)] = None
    proto_paths[_safe_proto_path(ctx.attr.govalidator_protos.label.workspace_root)] = None

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
              ctx.files.gogo_protos +
              ctx.files.govalidator_protos)

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
    proto_paths[_safe_proto_path(ctx.attr.gogo_protos.label.workspace_root)] = None
    proto_paths[_safe_proto_path(ctx.attr.govalidator_protos.label.workspace_root)] = None

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
              ctx.files.gogo_protos +
              ctx.files.govalidator_protos)

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

def _redoc_impl(ctx):
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

    pkg = ctx.attr.package if ctx.attr.package else "_".join(ctx.label.package.split("/"))
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

_redoc_gen = rule(
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
    implementation = _redoc_impl,
)

def _bindata_impl(ctx):
    pkg = ctx.attr.package if ctx.attr.package else ctx.label.package.split("/")[-1]

    inputs = ctx.files.srcs + [ctx.executable.bindata]
    ctx.action(
        inputs = inputs,
        outputs = [ctx.outputs.bindata],
        command = "%s -pkg %s -prefix %s -o %s %s" % (
            ctx.executable.bindata.path,
            pkg,
            ctx.label.package,
            ctx.outputs.bindata.path,
            " ".join([src.path for src in ctx.files.srcs]),
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
        "package": attr.string(),
    },
    output_to_genfiles = True,
    outputs = {
        "bindata": "%{name}.go"
    },
    implementation = _bindata_impl,
)

def gogo_proto_library(
        name,
        mode = None,
        srcs = None,
        importpath = None,
        package = None,
        deps = None,
        pure_go_deps = None,
        visibility = None,
        with_grpc = False,
        with_validators = False,
        with_gateway = False,
        with_swagger = False,
        with_rpc_forms = False):
    if not name:
        fail("name is required", "name")
    if mode and mode not in ["fast", "faster", "slick"]:
        fail("mode must be \"fast\", \"faster\", or \"slick\"", "mode")
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

    if with_validators:
        proto_outs += [s[:-len(".proto")] + ".validator.pb.go" for s in srcs]

    proto_name = name + "_proto"
    _proto_gen(
        name = proto_name,
        mode = mode,
        srcs = srcs,
        deps = proto_deps,
        importpath = importpath,
        outs = proto_outs,
        with_grpc = with_grpc or with_gateway or with_rpc_forms,
        with_validators = with_validators,
        with_rpc_forms = with_rpc_forms,
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

        redoc_outs = [s[:-len(".proto")] + ".swagger.go"
              for s in srcs]
        redoc_name = name + "_swagger_redoc"
        _redoc_gen(
            name = redoc_name,
            srcs = [":" + swagger_name],
            package = package,
        )
        lib_srcs += [":" + redoc_name]

    go_library(
        name = name,
        srcs = lib_srcs,
        deps = full_deps,
        importpath = importpath,
        visibility = visibility,
    )

def gogo_bindata_library(
        name,
        srcs = None,
        importpath = None,
        package = None,
        visibility = None):
    if not name:
        fail("name is required", "name")
    if not srcs:
        fail("srcs required", "srcs")

    _bindata_gen(
        name = name + "_bindata",
        srcs = srcs,
        package = package,
    )

    go_library(
        name = name,
        srcs = [":" + name + "_bindata"],
        importpath = importpath,
        visibility = visibility,
    )

_gogo_protobuf_repositories = {
    "github.com/gogo/letmegrpc":              "40744febf48274d7a07f81fb6570668ed1c1491f",
    "github.com/gogo/protobuf":               "2adc21fd136931e0388e278825291678e1d98309",
    "github.com/golang/glog":                 "23def4e6c14b4da8ac2ed8007337bc5eb5007998",
    "github.com/golang/protobuf":             "83cd65fc365ace80eb6b6ecfc45203e43edfbc70",
    "github.com/google/protobuf":             "6699f2cf64c656d96f4d6f93fa9563faf02e94b4",
    "github.com/grpc-ecosystem/grpc-gateway": "f2862b476edcef83412c7af8687c9cd8e4097c0f",
    "github.com/jteeuwen/go-bindata":         "a0ff2567cfb70903282db057e799fd826784d41d",
    "github.com/mwitkow/go-proto-validators": "a55ca57f374a8846924b030f534d8b8211508cf0",
    "golang.org/x/net":                       "5961165da77ad3a2abf3a77ea904c13a76b0b073",
    "golang.org/x/text":                      "e113a52b01bdd1744681b6ce70c2e3d26b58d389",
    "google.golang.org/genproto":             "411e09b969b1170a9f0c467558eb4c4c110d9c77",
    "google.golang.org/grpc":                 "7db1564ba1229bc42919bb1f6d9c4186f3aa8678",
}

def gogo_protobuf_repositories():
    for importpath, commit in _gogo_protobuf_repositories.items():
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
