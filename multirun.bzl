"""
Multirun is a rule for running multiple commands in a single invocation. This
can be very useful for something like running multiple linters or formatters
in a single invocation.
"""

load("@bazel_skylib//lib:shell.bzl", "shell")
load("//internal:constants.bzl", "RUNFILES_PREFIX")


def _multirun_impl(ctx):
    instructions_file = ctx.actions.declare_file(ctx.label.name + ".json")
    runner_info = ctx.attr._runner[DefaultInfo]
    runner_exe = runner_info.files_to_run.executable

    runfiles = ctx.runfiles(files = [instructions_file, runner_exe])
    runfiles = runfiles.merge(ctx.attr._bash_runfiles[DefaultInfo].default_runfiles)
    runfiles = runfiles.merge(runner_info.default_runfiles)

    for data_dep in ctx.attr.data:
        default_runfiles = data_dep[DefaultInfo].default_runfiles
        if default_runfiles != None:
            runfiles = runfiles.merge(default_runfiles)

    commands = []
    tagged_commands = []
    runfiles_files = []
    for command in ctx.attr.commands:
        tagged_commands.append(struct(tag = str(command.label), command = command))

    for tag_command in tagged_commands:
        command = tag_command.command
        tag = tag_command.tag

        default_info = command[DefaultInfo]
        if default_info.files_to_run == None:
            fail("%s is not executable" % command.label, attr = "commands")
        exe = default_info.files_to_run.executable
        if exe == None:
            fail("%s does not have an executable file" % command.label, attr = "commands")
        runfiles_files.append(exe)

        default_runfiles = default_info.default_runfiles
        if default_runfiles != None:
            runfiles = runfiles.merge(default_runfiles)
        commands.append(struct(
            tag = tag,
            path = exe.short_path,
        ))

    if ctx.attr.jobs < 0:
        fail("'jobs' attribute should be at least 0")

    jobs = ctx.attr.jobs
    instructions = struct(
        commands = commands,
        jobs = jobs,
        print_command = ctx.attr.print_command,
    )
    ctx.actions.write(
        output = instructions_file,
        content = instructions.to_json(),
    )

    script = 'exec ./%s -f %s "$@"\n' % (shell.quote(runner_exe.short_path), shell.quote(instructions_file.short_path))
    out_file = ctx.actions.declare_file(ctx.label.name + ".bash")
    ctx.actions.write(
        output = out_file,
        content = RUNFILES_PREFIX + script,
        is_executable = True,
    )
    return [
        DefaultInfo(
            files = depset([out_file]),
            runfiles = runfiles.merge(ctx.runfiles(files = runfiles_files + ctx.files.data)),
            executable = out_file,
        ),
    ]

multirun = rule(
    implementation = _multirun_impl,
    attrs = {
        "commands": attr.label_list(
            mandatory = False,
            allow_files = True,
            doc = "Targets to run",
            cfg = "target",
        ),
        "data": attr.label_list(
            doc = "The list of files needed by the commands at runtime. See general comments about `data` at https://docs.bazel.build/versions/master/be/common-definitions.html#common-attributes",
            allow_files = True,
        ),
        "jobs": attr.int(
            default = 1,
            doc = "The expected concurrency of targets to be executed. Default is set to 1 which means sequential execution. Setting to 0 means that there is no limit concurrency.",
        ),
        "print_command": attr.bool(
            default = True,
            doc = "Print what command is being run before running it. Only for sequential execution.",
        ),
        "_bash_runfiles": attr.label(
            default = Label("@bazel_tools//tools/bash/runfiles"),
        ),
        "_runner": attr.label(
            default = Label("//internal:multirun"),
            cfg = "host",
            executable = True,
        ),
    },
    executable = True,
)
