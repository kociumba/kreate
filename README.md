# kreate

kreate is a simple build system, a hybrid between [meson](https://github.com/mesonbuild/meson) and [nob.h](https://github.com/tsoding/nob.h)

It's written in d to take advantage of `rdmd`, which essentially turns d into a pseudo scripting language(still better than python)

To use kreate, simply copy `kreate.d` into your project, import it into your build script (e.g., `build.d`), and run it with rdmd `rdmd build.d`.

If you want faster builds you can compile this system using something like `dmd build.d -i kreate.d`, this skips rdmd having rebuild your build system but also locks your confiuguration untill you rebuild manually.

**Example build:**

```d:build.d
module build;

import kreate; // imports can be relative paths when using rdmd

void main(string[] args) {
    project("gabagool", "0.0.1", ["d", "go"], args); // create a sample project

    executable("myapp", ["src/main.odin"]); // kreate has  basic support for d, go and odin, anything else requires using custom targets

    customTarget("odin-docs", [findFile("main.odin")], "src/main.odin-doc", ["odin", "doc", "src", "-out:main"]);

    kreateInit(); // if not initialized kreate will not do anything
}
```

If you pass the `args` from your main to the kreate `project`, you can use cli commands to control what kreate does.

This means you can use it like this: `rdmd build.d build`

Right now there are 2 built in commands:

- `build`: simply builds all targets
- `clean`: removes the bin and build directories(by default kreate puts any internal files in the build directory and any executable output into the bin directory)

you can also use flags to force certain behaviour:

- `-f` or `--force` to force a rebuild not matter what the checksums checks return
- `-g` or `--graph` prints out the dependency graph created by kreate, usefull for debugging
