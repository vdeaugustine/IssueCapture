#!/usr/bin/env python3
"""Generate the native Unity link fixture with the real postprocessor; does not run tests."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile
import os


def run(*arguments, **options):
    subprocess.run([str(argument) for argument in arguments], check=True, **options)


def compile_processor(repository, contents, scratch):
    references = list((contents / "NetStandard/ref/2.1.0").glob("*.dll"))
    references += list((contents / "Managed/UnityEngine").glob("*.dll"))
    references.append(contents / "Tools/BuildPipeline/UnityEditor.iOS.Extensions.Xcode.dll")
    assembly = scratch / "Postprocessor.dll"
    arguments = ["-nologo", "-target:library", "-langversion:9",
                 "-define:UNITY_IOS,UNITY_EDITOR", f"-out:{assembly}"]
    arguments += [f"-r:{reference}" for reference in references]
    arguments += [str(path) for path in (repository / "Unity/Editor").glob("*.cs")]
    response = scratch / "compiler.rsp"
    response.write_text("\n".join(f'"{argument}"' for argument in arguments))
    run(contents / "NetCoreRuntime/dotnet", contents / "DotNetSdkRoslyn/csc.dll", f"@{response}")
    return assembly


def configure_fixture(repository, contents, scratch, output, assembly):
    driver = scratch / "Configure.cs"
    driver.write_text('''using System;
using System.IO;
using System.Reflection;
class Configure {
    static void Main(string[] args) {
        var type = Assembly.LoadFrom(args[0]).GetType("VinWare.IssueCapture.Editor.IssueCaptureBuildProcessor");
        var flags = BindingFlags.NonPublic | BindingFlags.Static;
        type.GetMethod("CopySources", flags).Invoke(null, new object[] {args[1], args[2] + "/IssueCaptureSupport"});
        string path = args[2] + "/UnityBridgeHost.xcodeproj/project.pbxproj";
        type.GetMethod("ConfigureProject", flags).Invoke(null, new object[] {path, File.ReadAllText(path)});
    }
}
''')
    executable = scratch / "Configure.exe"
    mono = contents / "MonoBleedingEdge/bin"
    run(mono / "mcs", f"-out:{executable}", driver)
    environment = dict(os.environ)
    environment["MONO_PATH"] = os.pathsep.join(str(contents / path) for path in
        ["Managed/UnityEngine", "Tools/BuildPipeline"])
    run(mono / "mono", executable, assembly, repository, output, env=environment)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--unity", required=True, type=Path, help="Path to Unity 6 Unity.app")
    parser.add_argument("--output", required=True, type=Path, help="New fixture directory (must not exist)")
    arguments = parser.parse_args()
    repository = Path(__file__).resolve().parent.parent
    output = arguments.output.resolve()
    if output.exists():
        parser.error("Output already exists; choose a fresh directory.")
    contents = arguments.unity.resolve() / "Contents"
    shutil.copytree(repository / "Unity/Native~/Fixture", output)
    run("xcodegen", "generate", "--spec", output / "project.yml")
    with tempfile.TemporaryDirectory(prefix="issuecapture-fixture-") as directory:
        scratch = Path(directory)
        assembly = compile_processor(repository, contents, scratch)
        configure_fixture(repository, contents, scratch, output, assembly)
    print(f"Ready: {output / 'UnityBridgeHost.xcodeproj'} (scheme UnityBridgeHost)")


if __name__ == "__main__":
    main()
