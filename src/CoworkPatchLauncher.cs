using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows.Forms;

internal class CoworkPatchLauncher : Form
{
    readonly string package;
    readonly Button install = new Button();
    readonly Label status = new Label();
    readonly ProgressBar progress = new ProgressBar();
    bool busy;

    [STAThread]
    static void Main()
    {
        Application.EnableVisualStyles();
        Application.Run(new CoworkPatchLauncher());
    }

    CoworkPatchLauncher()
    {
        using (var reader = new StreamReader(typeof(CoworkPatchLauncher).Assembly.GetManifestResourceStream("ArchiveName")))
            package = reader.ReadToEnd().Trim();
        if (!Regex.IsMatch(package, @"^[A-Za-z0-9][A-Za-z0-9._-]+$"))
            throw new InvalidDataException("Invalid embedded archive name.");
        Text = "Cowork VM \u8865\u4e01\u5b89\u88c5";
        ClientSize = new Size(520, 220);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
        var heading = new Label { Text = "Cowork VM", Font = new Font("Segoe UI", 18),
            Location = new Point(24, 18), AutoSize = true };
        status.SetBounds(24, 65, 470, 60);
        status.Text = "\u8bf7\u5148\u5b89\u88c5 Claude Desktop\uff0c\u5e76\u5b8c\u5168\u9000\u51fa Claude\u3002";
        progress.SetBounds(24, 133, 470, 16);
        install.SetBounds(370, 165, 124, 34);
        install.Text = "\u5b89\u88c5";
        install.Click += async delegate { await Install(); };
        Controls.AddRange(new Control[] { heading, status, progress, install });
        FormClosing += delegate(object sender, FormClosingEventArgs e) { if (busy) e.Cancel = true; };
    }

    async Task Install()
    {
        busy = true;
        install.Enabled = false;
        progress.Style = ProgressBarStyle.Marquee;
        status.Text = "\u6b63\u5728\u6821\u9a8c\u3001\u89e3\u538b\u548c\u5b89\u88c5\uff0c\u8bf7\u7b49\u5f85\u2026";
        string staging = Path.Combine(Path.GetTempPath(), "CoworkPatch-" + Guid.NewGuid().ToString("N"));
        try
        {
            await Task.Run(delegate
            {
                int partCount;
                long archiveSize;
                string expectedHash;
                using (var metadata = new StreamReader(typeof(CoworkPatchLauncher).Assembly.GetManifestResourceStream("ArchiveParts")))
                {
                    partCount = Int32.Parse(metadata.ReadLine());
                    archiveSize = Int64.Parse(metadata.ReadLine());
                }
                using (var expected = new StreamReader(typeof(CoworkPatchLauncher).Assembly.GetManifestResourceStream("ArchiveHash")))
                    expectedHash = expected.ReadToEnd().Trim();
                string archive = PrepareArchive(AppDomain.CurrentDomain.BaseDirectory, staging, package, partCount, archiveSize, expectedHash);
                long expanded = 0;
                using (var zip = ZipFile.OpenRead(archive))
                    foreach (var entry in zip.Entries) expanded = checked(expanded + entry.Length);
                string temporaryDrive = Path.GetPathRoot(staging);
                string targetDrive = Path.GetPathRoot(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData));
                bool sameDrive = String.Equals(temporaryDrive, targetDrive, StringComparison.OrdinalIgnoreCase);
                long margin = 512L * 1024 * 1024;
                if (new DriveInfo(temporaryDrive).AvailableFreeSpace < checked(expanded * (sameDrive ? 2 : 1) + margin) ||
                    (!sameDrive && new DriveInfo(targetDrive).AvailableFreeSpace < expanded + margin))
                    throw new IOException("\u78c1\u76d8\u7a7a\u95f4\u4e0d\u8db3\uff0c\u9700\u8981\u4e3a\u89e3\u538b\u548c\u5b89\u88c5\u5404\u9884\u7559\u4e00\u4efd VM \u7a7a\u95f4\u3002");
                ZipFile.ExtractToDirectory(archive, staging);
                string script = Path.Combine(staging, package, "Install-Cowork-VM.ps1");
                var start = CreateInstallStartInfo(script);
                start.UseShellExecute = false;
                start.CreateNoWindow = true;
                start.RedirectStandardOutput = true;
                start.RedirectStandardError = true;
                using (var process = Process.Start(start))
                {
                    Task<string> output = process.StandardOutput.ReadToEndAsync();
                    Task<string> error = process.StandardError.ReadToEndAsync();
                    process.WaitForExit();
                    Task.WaitAll(output, error);
                    string log = staging + ".log";
                    File.WriteAllText(log, output.Result + Environment.NewLine + error.Result);
                    if (process.ExitCode != 0) throw new IOException(error.Result + "\r\nLog: " + log);
                }
            });
            status.Text = "\u5b89\u88c5\u5b8c\u6210\u3002\u53ef\u4ee5\u6253\u5f00 Claude Desktop \u4f7f\u7528 Cowork\u3002";
            install.Text = "\u5df2\u5b89\u88c5";
        }
        catch (Exception error)
        {
            status.Text = "\u5b89\u88c5\u672a\u5b8c\u6210\u3002";
            MessageBox.Show(this, error.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
            install.Enabled = true;
        }
        finally
        {
            // Never follow unexpected junctions during temporary-file cleanup.
            try { DeletePlainDirectory(staging); } catch { }
            busy = false;
            progress.Style = ProgressBarStyle.Blocks;
        }
    }

    // Pass the directory explicitly, including for ZIPs containing older scripts.
    static ProcessStartInfo CreateInstallStartInfo(string script)
    {
        script = Path.GetFullPath(script);
        return new ProcessStartInfo(
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe"),
            "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + script +
            "\" -PackageDirectory \"" + Path.GetDirectoryName(script) + "\"");
    }
    // Split files are concatenated verbatim; the embedded SHA-256 authenticates the complete ZIP.
    static string PrepareArchive(string directory, string staging, string name, int count, long size, string expectedHash)
    {
        if (!Regex.IsMatch(name, @"^[A-Za-z0-9][A-Za-z0-9._-]+$") || count < 0 || count > 999 || size <= 0)
            throw new InvalidDataException("Invalid archive metadata.");
        string archive = Path.Combine(directory, name + ".zip");
        if (!File.Exists(archive))
        {
            if (count == 0) throw new IOException("Keep the installer and its ZIP in the same directory.");
            long total = 0;
            for (int i = 1; i <= count; i++)
            {
                string part = archive + "." + i.ToString("D3");
                AssertPlainPath(part);
                if (!File.Exists(part)) throw new IOException("Missing archive part: " + Path.GetFileName(part));
                total = checked(total + new FileInfo(part).Length);
            }
            if (total != size) throw new IOException("Archive parts have an unexpected total size.");
            AssertPlainPath(staging);
            if (new DriveInfo(Path.GetPathRoot(staging)).AvailableFreeSpace < checked(size + 512L * 1024 * 1024))
                throw new IOException("Not enough temporary disk space to combine archive parts.");
            Directory.CreateDirectory(staging);
            string combined = Path.Combine(staging, "payload.zip");
            using (var output = new FileStream(combined, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                for (int i = 1; i <= count; i++)
                    using (var input = File.OpenRead(archive + "." + i.ToString("D3"))) input.CopyTo(output);
            archive = combined;
        }
        AssertPlainPath(archive);
        if (new FileInfo(archive).Length != size) throw new IOException("Archive size mismatch.");
        using (var input = File.OpenRead(archive))
        using (var sha = SHA256.Create())
        {
            string hash = BitConverter.ToString(sha.ComputeHash(input)).Replace("-", "");
            if (!String.Equals(hash, expectedHash, StringComparison.OrdinalIgnoreCase))
                throw new IOException("Archive SHA-256 mismatch. Download the complete files again.");
        }
        return archive;
    }

    static void AssertPlainPath(string path)
    {
        for (string current = Path.GetFullPath(path); !String.IsNullOrEmpty(current); current = Path.GetDirectoryName(current))
            if ((File.Exists(current) || Directory.Exists(current)) &&
                (File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                throw new IOException("Reparse points are not supported: " + current);
    }

    static void DeletePlainDirectory(string path)
    {
        if (!Directory.Exists(path)) return;
        if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0) return;
        foreach (string file in Directory.GetFiles(path))
            if ((File.GetAttributes(file) & FileAttributes.ReparsePoint) == 0) File.Delete(file);
        foreach (string directory in Directory.GetDirectories(path)) DeletePlainDirectory(directory);
        Directory.Delete(path, false);
    }
}
