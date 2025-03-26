module kreate;

import std.stdio;
import std.algorithm;
import std.datetime.systime;
import std.datetime.timezone;
import core.time;
import core.stdc.stdlib;
import std.string;
import std.array;
import std.file;
import std.digest.md;
import std.conv;
import std.path;
import std.process;

/// main project structure, you never have to interact with it, it is managed by kreate
struct Project {
    string name;
    string ver; // TODO: this versioning is required right now, but not used | remove or find a use
    string buildDir;
    string binDir;
    string[] targetLangs;
    string[] cliArgs;
}

/// the instance of `Project` managed by create
Project projectConfig = Project(null);

/// Represents a language with an internal name and allowed extensions
struct Lang {
    string name;
    string[] extensions;
}

/// type of a target, used to distinguish what to build when using the support for d, go and odin
enum TargetType {
    EXECUTABLE,
    STATIC_LIB,
    DYNAMIC_LIB,
    CUSTOM,
}

/// represents a target, any target created can be used as a dependency and every build item is a target
struct Target {
    string name;
    string[] sourceFiles;
    TargetType targetType;
    string outputFile;
    Target[] dependencies;
    string[] flags;
    string[] customCommand;
    string mainDir;
    string[] importPaths; // TODO: actually use this for -I or something
}

/// list of created targets
Target[] targets;

const auto go = Lang("go", [".go"]);
const auto d = Lang("d", [".d"]);
const auto odin = Lang("odin", [".odin"]);

Lang[] supported = [go, d, odin];

/// provides basic logging functionality used by kreate
/// 
/// **IMPORTANT** `Log.fatal()` exits with `exit(1)` after logging. 
struct Log {
    static const string infoCol = "\x1B[38;5;157m";
    static const string warnCol = "\x1B[38;5;214m";
    static const string fataCol = "\x1B[38;5;196m";
    static const string erroCol = "\x1B[38;5;202m";
    static const string okCol = "\x1B[38;5;154m";
    static const string reset = "\x1B[0m";
    static const string dim = "\x1B[2m";
    static const string clearLine = "\x1B[2K";

    /// make this noop for now
    static string timestamp() {
        auto now = Clock.currTime();
        // return now.toString();
        return "";
    }

    /// logs an info message
    static void info(string msg) {
        writeln(timestamp(), infoCol, "[INFO] ", reset, msg);
    }

    /// logs a warning message
    static void warn(string msg) {
        writeln(timestamp(), warnCol, "[WARN] ", reset, msg);
    }

    /// logs an error message
    static void error(string msg) {
        writeln(timestamp(), erroCol, "[ERRO] ", reset, msg);
    }

    /// logs a fatal error message and exits using `exit(1)`
    static void fatal(string msg) {
        writeln(timestamp(), fataCol, "[FATA] ", reset, msg);
        exit(1);
    }
}

/// creates a directory if it doesn't exist
void k_mkdir(string path) {
    if (!exists(path)) {
        mkdir(path);
    }
}

/// drops a * gitignore into a directory, this is a trick from meson,
/// the gitignore ignores the whole directory from within itself so it's never included with no external gitignores
void dropKreateGitignore(string path) {
    string gitignore = "# This file is autogenerated by kreate, any edits will be overwritten!\n*";
    std.file.write(path ~ "/.gitignore", gitignore);
}

/// creates a kreate project, used for setting up things like supported languages or passing arguments to kreate
void project(string name,
    string ver,
    string[] targetLangs,
    string[] args = null,
    string buildDir = "build",
    string binDir = "bin"
) {
    if (projectConfig != Project(null)) {
        Log.fatal("project can only be called once in a kreate build system\n 
        ℹ️  If you are trying to add build targets use: staticLib(), dynamicLib(), executable(), customTarget()");
    }

    auto unsupported = targetLangs.filter!(
        targetLang =>
            !supported.canFind!(lang => lang.name == targetLang)
    ).array;

    if (unsupported.length > 0) {
        string langList;
        foreach (lang; unsupported) {
            langList ~= "  - " ~ lang ~ "\n";
        }
        Log.fatal(format("use of an unsupported language(s):\n%s
        ℹ️  If you want to use an unsupported language, you need to create a custom target: customTarget()",
                langList));
    }

    k_mkdir(buildDir);
    dropKreateGitignore(buildDir);
    k_mkdir(binDir);
    dropKreateGitignore(binDir);

    projectConfig = Project(name = name,
        ver,
        buildDir,
        binDir,
        targetLangs,
        args
    );
}

/// utils for finding singular args
bool hasArg(string command) {
    foreach (arg; projectConfig.cliArgs) {
        if (arg == command)
            return true;
    }
    return false;
}

/// utils for finding if we have a subcommand like this `rdmd build.d build`
bool hasSubcommand(string command) {
    return projectConfig.cliArgs[1] == command;
}

/// represents a file checksum,
/// 
/// kreate only really uses the checksum field, but it holds some usefull information about a file
struct FileChecksum {
    string filePath;
    string checksum;
    SysTime lastModified;
}

/// creates a checksum from a file
FileChecksum calculateChecksum(string filePath) {
    ubyte[] content = cast(ubyte[]) std.file.read(filePath);

    auto md5 = new MD5Digest();
    auto hash = md5.digest(content);
    string checksum = toHexString(hash).dup;

    SysTime lastModified = std.file.timeLastModified(filePath);

    return FileChecksum(filePath, checksum, lastModified);
}

/// saves the checksum to the managed buildDir/checksums directory
void saveChecksum(FileChecksum checksum, string buildDir) {
    string checksumDir = buildDir ~ "/checksums";
    k_mkdir(checksumDir);

    string checksumPath = checksumDir ~ "/" ~ std.path.baseName(checksum.filePath) ~ ".#";

    std.file.write(checksumPath, checksum.filePath ~ "\n" ~ checksum.checksum ~ "\n" ~
            checksum.lastModified.toString());
}

/// loads a given checksum for comparison
FileChecksum loadChecksum(string filePath, string buildDir) {
    string checksumDir = buildDir ~ "/checksums";
    string checksumPath = checksumDir ~ "/" ~ std.path.baseName(filePath) ~ ".#";

    if (!std.file.exists(checksumPath)) {
        return FileChecksum("", "", SysTime.init);
    }

    string[] lines = std.file.readText(checksumPath).splitLines();
    if (lines.length < 3) {
        return FileChecksum("", "", SysTime.init);
    }

    SysTime lastModified;
    try {
        lastModified = SysTime.fromISOExtString(lines[2]);
    } catch (Exception e) {
        lastModified = SysTime.init;
    }

    return FileChecksum(lines[0], lines[1], lastModified);
}

/// determines if a target needs to be rebilt based on the existance of it's output and the checksum data
bool needsRebuild(string filePath, string buildDir) {
    if (hasArg("-f") | hasArg("--force"))
        return true;

    FileChecksum oldChecksum = loadChecksum(filePath, buildDir);
    FileChecksum newChecksum = calculateChecksum(filePath);

    return oldChecksum.checksum != newChecksum.checksum;
}

/// builds and executes a build command for a given target
bool executeBuildCommand(Target target) {
    write("Building target: " ~ target.name ~ "...");

    auto start = MonoTime.currTime;
    string[] cmd;
    string lang = detectLanguage(target.sourceFiles);

    if (target.targetType == TargetType.CUSTOM) {
        cmd = target.customCommand;
    } else if (lang == "d") {
        cmd = buildDCommand(target);
    } else if (lang == "go") {
        cmd = buildGoCommand(target);
    } else if (lang == "odin") {
        cmd = buildOdinCommand(target);
    } else {
        Log.fatal("Unsupported language: " ~ lang); // should always fail before this check
        return false;
    }

    // i don't have any ideas how to integrate this into the new logging, but it should be availible 
    // Log.info("Executing: " ~ cmd.join(" "));
    auto result = execute(cmd);
    if (result.status != 0) {
        Log.error(Log.clearLine
                ~ "\rBuilding target: "
                ~ target.name
                ~ Log.erroCol
                ~ " [ERRO] "
                ~ Log.reset
                ~ ":\n"
                ~ result.output);
        return false;
    }

    auto duration = MonoTime.currTime - start;
    Log.info(Log.clearLine
            ~ "\rBuilding target: "
            ~ target.name
            ~ Log.okCol
            ~ " [OK] "
            ~ Log.reset
            ~ Log.dim
            ~ duration.toString()
            ~ Log.reset);
    return true;
}

/// builds a basic d compilation command
string[] buildDCommand(Target target) {
    string[] cmd = ["dmd"];

    if (target.flags.length > 0) {
        cmd ~= target.flags;
    }

    if (target.targetType == TargetType.STATIC_LIB) {
        cmd ~= "-lib";
    } else if (target.targetType == TargetType.DYNAMIC_LIB) {
        cmd ~= "-shared";
    }

    cmd ~= "-of=" ~ target.outputFile;
    cmd ~= target.sourceFiles;

    foreach (dep; target.dependencies) {
        if (dep.targetType == TargetType.STATIC_LIB || dep.targetType == TargetType.DYNAMIC_LIB) {
            cmd ~= "-L-L" ~ dirName(dep.outputFile);

            string libName = baseName(dep.outputFile);
            if (libName.startsWith("lib")) {
                libName = libName[3 .. $];
            }

            libName = stripExtension(libName);
            cmd ~= "-L-l" ~ libName;
        }
    }

    return cmd;
}

/// builds a basic go compilation command
string[] buildGoCommand(Target target) {
    string mainDir = inferMainDir(target.sourceFiles);
    string[] cmd = ["go", "build"];

    cmd ~= "-C";
    cmd ~= mainDir;

    if (target.flags.length > 0) {
        cmd ~= target.flags;
    }

    if (target.targetType == TargetType.DYNAMIC_LIB) {
        cmd ~= "-buildmode=c-shared";
    } else if (target.targetType == TargetType.STATIC_LIB) {
        cmd ~= "-buildmode=c-archive";
    }

    auto absOutput = asNormalizedPath(asAbsolutePath(target.outputFile));

    cmd ~= "-o";
    cmd ~= absOutput.array;
    cmd ~= ".";

    return cmd;
}

/// builds a basic odin compilation command
string[] buildOdinCommand(Target target) {
    string mainDir = inferMainDir(target.sourceFiles);
    string[] cmd = ["odin", "build ", mainDir];

    if (target.flags.length > 0) {
        cmd ~= target.flags;
    }

    if (target.targetType == TargetType.STATIC_LIB) {
        cmd ~= "-build-mode:static";
    } else if (target.targetType == TargetType.DYNAMIC_LIB) {
        cmd ~= "-build-mode:shared";
    }

    cmd ~= "-out:" ~ target.outputFile;

    foreach (dep; target.dependencies) {
        if (dep.targetType == TargetType.STATIC_LIB) {
            cmd ~= "-library:" ~ dep.outputFile;
        }
    }

    return cmd;
}

/// infers the main directory of a list of files
/// 
/// lacks any actual detection, only returns the directory of the first file in the array
string inferMainDir(string[] sourceFiles) {
    if (sourceFiles.length == 0) {
        return ".";
    }

    // needs better detection here, but for now it's fine
    return dirName(sourceFiles[0]);
}

/// detects the language of a file based on it's extension
string detectLanguage(string[] sourceFiles) {
    if (sourceFiles.length == 0) {
        Log.fatal("No source files specified");
    }

    string ext = std.path.extension(sourceFiles[0]);

    foreach (lang; supported) {
        if (lang.extensions.canFind(ext)) {
            if (projectConfig.targetLangs.canFind(lang.name)) {
                return lang.name;
            }
        }
    }

    auto name = replace(ext, ".", "");

    Log.fatal("Unsupported or not enabled language detected: " ~ name);
    return ""; // doesn't matter what we return since Log.fatal exits either way
}

/// determines if a given target needs to be rebuilt
bool needsRebuildTarget(ref Target target) {
    string buildDir = projectConfig.buildDir;

    if (!std.file.exists(target.outputFile)) {
        return true;
    }

    foreach (sourceFile; target.sourceFiles) {
        if (needsRebuild(sourceFile, buildDir)) {
            return true;
        }
    }

    foreach (ref dependency; target.dependencies) {
        if (dependency.name in rebuiltTargets) {
            return true;
        }
    }

    return false;
}

/// creates a managed executable target
Target executable(string name, string[] sourceFiles, Target[] dependencies = [], string[] importPaths = [
    ]) {
    string outputFile = projectConfig.binDir ~ "/" ~ name;
    version (Windows) {
        outputFile ~= ".exe";
    }

    string lang = detectLanguage(sourceFiles);
    string[] flags;

    if (lang == "d") {
        flags = ["-O", "-release"];
    } else if (lang == "go") {
        flags = ["-ldflags", "-s -w"];
    } else if (lang == "odin") {
        flags = ["-o:speed"];
    }

    string mainDir = inferMainDir(sourceFiles);

    Target target = Target(
        name,
        sourceFiles,
        TargetType.EXECUTABLE,
        outputFile,
        dependencies,
        flags,
        [],
        mainDir,
        importPaths
    );

    targets ~= target;
    return target;
}

/// creates a managed static library target
Target staticLib(string name, string[] sourceFiles, Target[] dependencies = [], string[] importPaths = [
    ]) {
    string outputFile = projectConfig.buildDir ~ "/lib" ~ name ~ ".a";

    string lang = detectLanguage(sourceFiles);
    string[] flags;

    if (lang == "d") {
        flags = ["-O", "-release"];
    } else if (lang == "go") {
        flags = ["-ldflags", "-s -w"];
    } else if (lang == "odin") {
        flags = ["-o:speed"];
    }

    string mainDir = inferMainDir(sourceFiles);

    Target target = Target(
        name,
        sourceFiles,
        TargetType.STATIC_LIB,
        outputFile,
        dependencies,
        flags,
        [],
        mainDir,
        importPaths
    );

    targets ~= target;
    return target;
}

/// creates a managed dynamic library target
Target dynamicLib(string name,
    string[] sourceFiles,
    Target[] dependencies = [],
    string[] importPaths = []
) {
    string outputFile;
    version (Windows) {
        outputFile = projectConfig.buildDir ~ "/" ~ name ~ ".dll";
    } else version (OSX) {
        outputFile = projectConfig.buildDir ~ "/lib" ~ name ~ ".dylib";
    } else {
        outputFile = projectConfig.buildDir ~ "/lib" ~ name ~ ".so";
    }

    string lang = detectLanguage(sourceFiles);
    string[] flags;

    if (lang == "d") {
        flags = ["-O", "-release"];
    } else if (lang == "go") {
        flags = ["-ldflags", "-s -w"];
    } else if (lang == "odin") {
        flags = ["-o:speed"];
    }

    string mainDir = inferMainDir(sourceFiles);

    Target target = Target(
        name,
        sourceFiles,
        TargetType.DYNAMIC_LIB,
        outputFile,
        dependencies,
        flags,
        [],
        mainDir,
        importPaths
    );

    targets ~= target;
    return target;
}

/// creates a custom managed target, custom is used to any other language than d, go and odin
Target customTarget(string name,
    string[] sourceFiles,
    string outputFile,
    string[] customCommand,
    Target[] dependencies = []) {
    Target target = Target(
        name,
        sourceFiles,
        TargetType.CUSTOM,
        outputFile,
        dependencies,
        [],
        customCommand,
        inferMainDir(sourceFiles),
        []
    );

    targets ~= target;
    return target;
}

/// simple function that recursively finds a file in any location beneeth the current dir
/// Returns: the absolute path to the found file
/// Throws: if the path can not befound the function will `exit(1)`
string findFile(string name) {
    if (exists(name)) {
        return asNormalizedPath(asAbsolutePath(name)).array;
    }

    // very non c like, reminds me of kotlin
    auto entries = dirEntries(".", SpanMode.depth)
        .filter!(e => e.isFile && baseName(e.name) == baseName(name));
    if (!entries.empty) {
        return asNormalizedPath(asAbsolutePath(entries.front.name)).array;
    }

    Log.fatal("could not find: " ~ name ~ " in the current dir, ensure the file exists or use a simple relative path");
    return null;
}

/// does the same as `findFile` but searches in known global paths like for example the INCLUDE env var
/// Returns: the absolute path to the found file
/// Throws: if the path can not befound the function will `exit(1)`
string findGlobal(string name) {
    string searchPaths = environment.get("INCLUDE");
    if (searchPaths == null || searchPaths.empty) {
        Log.fatal("Environment variable INCLUDE is not set or is empty");
        return null;
    }

    auto searchDirs = split(searchPaths, pathSeparator);
    auto validDirs = searchDirs.filter!(a => !a.empty && isValidPath(a)).array;

    foreach (dir; validDirs) {
        string path = buildPath(dir, name);
        if (exists(path) && isFile(path)) {
            return asNormalizedPath(asAbsolutePath(path)).array;
        }
    }

    Log.fatal("Could not find: " ~ name ~ " in any of the directories in INCLUDE");
    return "";
}

Target[string] targetMap; // interesting way to do arrays, so essentially any array can be a map 🤷
Target[][string] dependentTargets;
bool[string] builtTargets;
bool[string] rebuiltTargets;

/// populates the dependency graph with data fro sorting
void buildDependencyGraph() {
    foreach (ref target; targets) {
        targetMap[target.name] = target;
        foreach (ref dep; target.dependencies) {
            dependentTargets[dep.name] ~= target;
        }
    }

    /// debug logic, left in couse it can be usefull
    if (hasArg("-g") | hasArg("--graph")) {
        writeln("dep graph: ", targetMap);
        writeln("dependents: ", dependentTargets);
    }
}

/// uses kahn's algorithm to sort the graph topologically eliminating duplicates
Target[] topologicalSort() {
    buildDependencyGraph();
    Target[] sortedOrder;
    Target[] queue;

    Target[][string] remainingDeps;
    foreach (ref target; targets) {
        remainingDeps[target.name] = target.dependencies.dup;
    }

    foreach (ref target; targets) {
        if (remainingDeps[target.name].length == 0) {
            queue ~= target;
        }
    }

    while (queue.length > 0) {
        Target current = queue[0];
        queue = queue[1 .. $];
        sortedOrder ~= current;

        if (current.name in dependentTargets) {
            foreach (ref dependent; dependentTargets[current.name]) {
                auto depName = dependent.name;
                remainingDeps[depName] = remainingDeps[depName].remove!(
                    d => d.name == current.name
                );

                if (remainingDeps[depName].length == 0) {
                    queue ~= dependent;
                }
            }
        }
    }

    if (sortedOrder.length != targets.length) {
        Log.fatal("Circular dependency detected in target graph");
        return [];
    }

    return sortedOrder;
}

/// executes the build of all targets or the ones that are passed in
void kreateBuild(string[] targetNames = []) {
    Target[] buildOrder;

    if (targetNames.length == 0) {
        buildOrder = topologicalSort();
        if (buildOrder.length == 0)
            return;
    } else {
        bool[string] toBuild;
        foreach (name; targetNames) {
            if (name !in targetMap) {
                Log.fatal("Target not found: " ~ name);
                return;
            }
            collectTargets(targetMap[name], toBuild);
        }
        buildOrder = topologicalSort().filter!(t => t.name in toBuild).array;
        if (buildOrder.length == 0)
            return;
    }

    foreach (ref target; buildOrder) {
        if (needsRebuildTarget(target)) {
            if (!executeBuildCommand(target)) {
                Log.fatal("Build failed for target: " ~ target.name);
                return;
            }

            rebuiltTargets[target.name] = true;
            builtTargets[target.name] = true;

            foreach (sourceFile; target.sourceFiles) {
                auto checksum = calculateChecksum(sourceFile);
                saveChecksum(checksum, projectConfig.buildDir);
            }
        } else {
            builtTargets[target.name] = true;
            Log.info("Target " ~ target.name ~ " is up to date");
        }
    }

    Log.info("Build completed successfully");
}

/// recursive target collection used for custom builds
void collectTargets(ref Target target, ref bool[string] toBuild) {
    toBuild[target.name] = true;
    foreach (ref dep; target.dependencies) {
        collectTargets(dep, toBuild);
    }
}

/// removes the configured bin and build directories and everything in them including kreate checksums 
void kreateClean() {
    if (std.file.exists(projectConfig.buildDir)) {
        std.file.rmdirRecurse(projectConfig.buildDir);
        Log.info("Removed build directory: " ~ projectConfig.buildDir);
    }

    if (std.file.exists(projectConfig.binDir)) {
        std.file.rmdirRecurse(projectConfig.binDir);
        Log.info("Removed bin directory: " ~ projectConfig.binDir);
    }

    Log.info("Clean completed successfully");
}

/// initializes and registers the kreate build system for execution
void kreateInit() {
    if (projectConfig.cliArgs.length > 1) {
        if (hasSubcommand("build")) {
            kreateBuild();
            return;
        }
        if (hasSubcommand("clean")) {
            kreateClean();
            return;
        }
    }

    Log.warn("cli arguments not forwarded to kreate, executing default build
    
        you can customize this behaviour by using the operation functions in your build script: kreateBuild(), ...
        or by forwarding cli arguments to the kreate project() function
    ");

    kreateBuild();
}
