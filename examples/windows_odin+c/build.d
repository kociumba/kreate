import kreate;
import std.path;
import std.format;
import std.stdio;

void main(string[] args) {
    project("odin+c", "1.0.0", ["odin"], args);

    // Define commands to build the C static library
    string compileCmd = format("zig cc -c %s -o %s/mylib.o -fno-sanitize=undefined",
        findFile("src/c/mylib.c"),
        projectConfig.buildDir);
    string archiveCmd = format("zig ar rcs %s/libmylib.a %s/mylib.o", projectConfig.buildDir, projectConfig
            .buildDir);
    string fullCmd = compileCmd ~ " && " ~ archiveCmd;

    // Custom target for the C static library
    auto myLibTarget = customTarget(
        "mylib",
        [findFile("src/c/mylib.c")],
        projectConfig.buildDir ~ "/libmylib.a",
        ["cmd", "/c", fullCmd]
    );
    
    // uses the new copyFile target, that is possible thanks to callback targets
    auto copyLibTarget = copyFile(
        projectConfig.buildDir ~ "/mylib.o",
        dirName(findFile("main.odin")) ~ "/mylib.o",
        [myLibTarget] // this essentially signals kreate that the file can not be copied until it has been created in this step
    );

    // Odin executable that depends on the C library
    auto odinApp = executable(
        "myapp-odin",
        [findFile("src/odin/main.odin")],
        [myLibTarget, copyLibTarget]
    );

    delPath(dirName(findFile("main.odin")) ~ "/mylib.o", [odinApp]);

    // kreateInit(); // experimental kreate feature eliminates the need to call kreateInit at the end of main
}
