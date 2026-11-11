using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("Claude Desktop Offline Installer (Unofficial)")]
[assembly: AssemblyProduct("Claude Desktop")]

internal static class OfflineLauncher
{
    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            bool extractOnly = args.Length == 2 && args[0] == "--extract-only";
            if (args.Length != 0 && !extractOnly)
                throw new ArgumentException("Usage: --extract-only <new-directory>");
            string directory = extractOnly
                ? Path.GetFullPath(args[1])
                : Path.Combine(Path.GetTempPath(), "Claude-Offline-" + Guid.NewGuid().ToString("N"));
            if (Directory.Exists(directory))
                throw new IOException("Extraction directory already exists: " + directory);
            Directory.CreateDirectory(directory);
            Extract("ClaudeSetup", Path.Combine(directory, "Claude Setup.exe"));
            Extract("ClaudeMsix", Path.Combine(directory, "Claude-x64.msix"));
            string code = Path.Combine(directory, "claude.exe");
            bool includesCode = Array.IndexOf(Assembly.GetExecutingAssembly().GetManifestResourceNames(), "ClaudeCodeBinary") >= 0;
            if (includesCode) Extract("ClaudeCodeBinary", code);
            if (extractOnly) return 0;

            // Retain extracted files because Setup may delegate to a child process.
            ProcessStartInfo start = new ProcessStartInfo(
                Path.Combine(directory, "Claude Setup.exe"),
                "-local-msix \"" + Path.Combine(directory, "Claude-x64.msix") + "\"");
            start.UseShellExecute = true;

            using (Process process = Process.Start(start))
            {
                process.WaitForExit();
                if (process.ExitCode != 0)
                    throw new InvalidOperationException("Claude Setup exited with code " + process.ExitCode);
            }
            VerifyInstalledMsix();
            if (includesCode)
            {
                string version = FileVersionInfo.GetVersionInfo(code).ProductVersion;
                Version parsed;
                if (!Version.TryParse(version, out parsed))
                    throw new InvalidOperationException("Invalid Claude Code version: " + version);
                version = parsed.ToString(3);
                string target = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "Claude-3p", "claude-code", version);
                Directory.CreateDirectory(target);
                File.Copy(code, Path.Combine(target, "claude.exe"), true);
            }
            return 0;
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "Claude Desktop Offline Installer",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    // Probe registration in the invoking user's context after the official Setup exits.
    private static void VerifyInstalledMsix()
    {
        var probe = new ProcessStartInfo(
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe"),
            "-NoProfile -NonInteractive -Command \"$p = Get-AppxPackage -Name Claude -ErrorAction Stop; " +
            "if ($p) { $p | Select-Object -ExpandProperty Version }\"");
        probe.UseShellExecute = false;
        probe.CreateNoWindow = true;
        probe.RedirectStandardOutput = true;
        probe.RedirectStandardError = true;
        using (var process = Process.Start(probe))
        {
            string output = process.StandardOutput.ReadToEnd();
            string error = process.StandardError.ReadToEnd();
            process.WaitForExit();
            string expected = Assembly.GetExecutingAssembly().GetName().Version.ToString();
            if (process.ExitCode != 0 || !String.Equals(output.Trim(), expected, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException(
                    "Official Setup returned, but Claude MSIX " + expected + " is not registered for this Windows user. " +
                    "Do not install the Cowork VM patch yet. Check the official Setup log and the account used for elevation. " +
                    "Detected package version: " + (String.IsNullOrWhiteSpace(output) ? "none" : output.Trim()) +
                    (String.IsNullOrWhiteSpace(error) ? "" : "; probe error: " + error.Trim()));
        }
    }
    private static void Extract(string resource, string destination)
    {
        using (Stream input = Assembly.GetExecutingAssembly().GetManifestResourceStream(resource))
        {
            if (input == null) throw new IOException("Missing resource: " + resource);
            using (FileStream output = new FileStream(destination, FileMode.CreateNew, FileAccess.Write))
                input.CopyTo(output);
        }
    }
}
