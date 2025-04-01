# kreate

kreate is a simple build system, a hybrid between [meson](https://github.com/mesonbuild/meson) and [nob.h](https://github.com/tsoding/nob.h)

It's written in D to take advantage of `rdmd`, which essentially turns D into a pseudo scripting language (still better than python)

To use kreate, simply copy `kreate.d` into your project, import it into your build script (e.g., `build.d`), and run it with rdmd `rdmd build.d`.

If you want faster builds, you can compile this system using something like `dmd build.d -i kreate.d`, this skips rdmd having to rebuild your build system but also locks your confiuguration untill you rebuild manually.

However, this is a matter of preference since rdmd should not rebuild the system if there are no changes detected.

### Why and how this works ?

The philosophy and design of kreate is a "managed script", 
so the execution pipeline works like this:

- import kreate (optionally use the `NO_EXPERIMENTAL` version when running/compiling)
- use your `main()` to define your build
- then at the end of your main kreate executes the build

This is why you can not just use kreate like nob.h where you can use arbiturary code in the execution flow.

#### Why ?

This design is used to ensure the builds have no cyclic dependencies and that the targets are always ordered in the optimal build order.

The drawback here is that configuration is more verbose since you must explicitly provide dependency information for each target.

### Example build script:

```d
module build;

import kreate; // imports can be relative paths when using rdmd

void main(string[] args) {
    project("gabagool", "0.0.1", ["odin"], args); // create a sample project with ODIN support

    auto odinApp = executable("myapp", ["src/main.odin"]); // kreate has  basic support for d, go and odin, anything else requires using custom targets

    // you can use the `findFile()` and `findGlobal()` functions to find files respectively in the current dir and below it or in directories from the `INCLUDE` env variable
    customTarget("odin-docs", [findFile("main.odin")], "src/main.odin-doc", ["odin", "doc", "src", "-out:main"]);

    // kreateInit(); // Not calling kreateInit since the experimental module destructor handles that for us 
}
```

> [!CAUTION]
> kreate currently uses an experimental module-level destructor to call `kreateInit()` for you when `main()` finishes. This is an opt-out experimental feature, to turn it off, use `-version=NO_EXPERIMENTAL` when compiling/running.

If you pass the `args` from your main to the `project` function, you can use cli commands to control what kreate does. For example `rdmd build.d build`, performs a build of all targets.

#### Callback targets

kreate has a new feature called callback targets, this means you can define targets with code callbacks, instead of only shell commands, example:

```d
auto customCallbackTarget = customCallback(
    "myCustomCallback",
    ["./sourceFile1", "./sourceFile2"],
    "./outputFile",
    (ref Target t) {
        // this is your callback, an Error return is expected 
        try {
            writeln(t.outputFile);
            return null;
        } catch {
            return new Error("could not print the output file of the target");
        }
    },
    [myDependency]
);
```
> [!NOTE]
> This is ofcourse an extreamly verbose example and this functionality comes with an (unfinished) set of helper targets, you can use in your build, so far there is:
>
> - `copyFile`: copies a file from a source into a destination
> - `delPath`: tries to remove a passed in path

## Subcommands:

Built into kreate there are:

- `build`: Simply builds all targets
- `clean`: Removes the bin and build directories (by default, kreate places internal files in build and executable output in bin)

to create your own subcommands use something like this to your build script:

```d
if (hasSubcommand("build-odin")) {
    kreateBuild([odinApp]);
    return; // has to return to a avoid kreate using it's default behaviour after it
}
```

then you can use this subcommand like so: `rdmd build.d build-odin`

> [!IMPORTANT]
> You can overrite the built in `build` and `clean` subcommands this way

## Flags:

Built-in flags are:

- `-f` or `--force` Forces a rebuild regardless of checksum comparisons.
- `-g` or `--graph` Prints the dependency graph created by kreate, useful for debugging.
- `-r` or `--release` Adds optimisation and "release" mode flags to builds of the supported languages.
- `--ignore-fatal` Continues execution after a fatal error.

> [!WARNING]
> `--ignore-fatal` can cause unexpected behaviour, since kreate will continiue on `Log.fatal()` which it wasn't designed to handle

To create custom flags, add something like this to your build script:

```d
if (hasArg("--hello") || hasArg("-h")) {
    writeln("hello")
}
```

## Examples

Right now there is a single example of building an odin+c executable in the [excamples](./examples/) directory.
To run this example simply `git clone` the repo and `cd` into it, the run `rdmd ./examples/windows_odin+c/build.d build`.

> [!NOTE]
> these examples will always try to use absolute paths and `findFile()`, this is because they are designed to be executable from the bottom of the repo, your builds will likely be simpler
