#if UNITY_IOS
using System;
using System.IO;
using System.Text.RegularExpressions;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEditor.iOS.Xcode;

namespace VinWare.IssueCapture.Editor
{
    /// <summary>Recreates native integration on every fresh Unity iOS export using the installed UPM package sources.</summary>
    public sealed class IssueCaptureBuildProcessor : IPostprocessBuildWithReport
    {
        private const string SupportDirectory = "IssueCaptureSupport";
        private const string Product = "IssueCaptureUnity";

        /// <summary>Runs after Unity writes the iOS project.</summary>
        public int callbackOrder => 900;

        /// <summary>Includes native capture only for Development Build; rejects reuse of an instrumented output folder.</summary>
        public void OnPostprocessBuild(BuildReport report)
        {
            if (report.summary.platform != BuildTarget.iOS) return;
            string output = report.summary.outputPath;
            bool development = (report.summary.options & BuildOptions.Development) != 0;
            Configure(output, development);
        }

        internal static void Configure(string output, bool development)
        {
            string projectPath = PBXProject.GetPBXProjectPath(output);
            string original = File.ReadAllText(projectPath);
            string support = Path.Combine(output, SupportDirectory);
            // Unity's append export can retain native files and package references from previous builds.
            if (Directory.Exists(support) || original.Contains(Product))
                throw new BuildFailedException("IssueCapture requires a fresh iOS export folder. Delete the previous export or choose a new folder, especially when switching Development Build off.");
            if (!development) return;
            if (!Version.TryParse(PlayerSettings.iOS.targetOSVersionString, out var version) || version < new Version(15, 0))
                throw new BuildFailedException("IssueCapture requires iOS 15+. Set the Unity deployment target explicitly; it is never raised automatically.");
            string source = UnityEditor.PackageManager.PackageInfo.FindForAssembly(typeof(IssueCaptureBuildProcessor).Assembly)?.resolvedPath;
            if (source == null) throw new BuildFailedException("Install IssueCapture through Unity Package Manager before exporting.");
            CopySources(source, support);
            ConfigureProject(projectPath, original);
        }

        private static void CopySources(string source, string support)
        {
            string package = Path.Combine(support, "Package");
            Directory.CreateDirectory(package);
            File.Copy(Path.Combine(source, "Package.swift"), Path.Combine(package, "Package.swift"));
            CopyDirectory(Path.Combine(source, "Sources"), Path.Combine(package, "Sources"));
            File.Copy(Path.Combine(source, "Unity/Native~/IssueCaptureUnity.mm"), Path.Combine(support, "IssueCaptureUnity.mm"));
        }

        private static void CopyDirectory(string source, string destination)
        {
            Directory.CreateDirectory(destination);
            foreach (string file in Directory.GetFiles(source, "*.swift"))
                File.Copy(file, Path.Combine(destination, Path.GetFileName(file)));
            foreach (string directory in Directory.GetDirectories(source))
                CopyDirectory(directory, Path.Combine(destination, Path.GetFileName(directory)));
        }

        private static void ConfigureProject(string path, string original)
        {
            var project = new PBXProject();
            project.ReadFromString(original);
            string framework = project.GetUnityFrameworkTargetGuid();
            string main = project.GetUnityMainTargetGuid();
            string adapter = SupportDirectory + "/IssueCaptureUnity.mm";
            project.AddFileToBuild(framework, project.AddFile(adapter, adapter, PBXSourceTree.Source));
            // Unity 6's PBX API only creates remote references. Replace this one known object
            // with Xcode's local-package object after letting Unity create product/build linkage.
            string package = project.AddRemotePackageReferenceAtRevision("https://github.com/vdeaugustine/IssueCapture.git", "local-source-snapshot");
            project.AddRemotePackageFrameworkToProject(framework, Product, package, false);
            project.SetBuildProperty(framework, "SWIFT_VERSION", "5.0");
            project.SetBuildProperty(main, "ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES", "YES");
            project.AddBuildProperty(framework, "OTHER_LDFLAGS", "-ObjC");
            string generated = ReplaceWithLocalPackage(project.WriteToString(), package);
            File.WriteAllText(path, generated);
        }

        private static string ReplaceWithLocalPackage(string project, string guid)
        {
            string pattern = @"(?m)^\s*" + Regex.Escape(guid) + @" /\*[^\r\n]*\*/ = \{\s*isa = XCRemoteSwiftPackageReference;.*?^\t\t\};";
            var matcher = new Regex(pattern, RegexOptions.Singleline | RegexOptions.Multiline);
            if (matcher.Matches(project).Count != 1)
                throw new BuildFailedException("Unexpected Unity PBX package format. IssueCapture did not write the project; use a supported Unity 6 exporter.");
            string local = "\t\t" + guid + " /* XCLocalSwiftPackageReference IssueCapture */ = {\n"
                + "\t\t\tisa = XCLocalSwiftPackageReference;\n"
                + "\t\t\trelativePath = IssueCaptureSupport/Package;\n\t\t};";
            return matcher.Replace(project, local, 1);
        }
    }
}
#endif
