using System;
using System.Diagnostics;
using System.IO;
using System.Management;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("HollowDrivers")]
[assembly: AssemblyProduct("HollowDrivers")]
[assembly: AssemblyDescription("Protege seus drivers e avisa quando algo der errado")]

namespace DG
{
    public static class ShellIdentity
    {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
        public static extern void SetCurrentProcessExplicitAppUserModelID(string appId);
    }

    // Usado pela interface (HollowDrivers.ps1) para a barra de título escura, sem compilar nada ao abrir.
    public static class Dwm
    {
        [DllImport("dwmapi.dll")]
        public static extern int DwmSetWindowAttribute(IntPtr h, int a, ref int v, int s);
    }

    static class Program
    {
        [STAThread]
        static int Main(string[] args)
        {
            string dir = AppDomain.CurrentDomain.BaseDirectory;
            if (args.Length > 0 && args[0] == "--uninstall") return Uninstaller.Run(dir);

            string ps1 = Path.Combine(dir, "HollowDrivers.ps1");
            if (!File.Exists(ps1))
            {
                MessageBox.Show("Arquivo HollowDrivers.ps1 não encontrado em:\n" + dir + "\n\nReinstale o HollowDrivers.",
                    "HollowDrivers", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
            string extra = "";
            foreach (string a in args) extra += " " + (a.Contains(" ") ? "\"" + a + "\"" : a);

            var psi = new ProcessStartInfo("powershell.exe",
                "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + ps1 + "\"" + extra);
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.WorkingDirectory = dir;
            Process.Start(psi);
            return 0;
        }
    }

    public static class Uninstaller
    {
        public static int Run(string dir)
        {
            if (MessageBox.Show("Desinstalar o HollowDrivers?", "HollowDrivers",
                    MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return 0;
            bool wipe = MessageBox.Show(
                "Apagar também o backup do driver de vídeo e as configurações?\n\nEscolha \"Não\" para manter o backup caso reinstale depois.",
                "HollowDrivers", MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes;

            FileStream maintenance;
            try { maintenance = Maintenance.Acquire(dir); }
            catch (Exception ex) { MessageBox.Show(ex.Message, "HollowDrivers"); return 1; }
            using (maintenance) {
            using (RegistryKey k = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", true))
            {
                if (k != null) k.DeleteValue("HollowDrivers", false);
            }
            Registry.CurrentUser.DeleteSubKeyTree(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\HollowDrivers", false);
            TryDelete(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "HollowDrivers.lnk"));
            TryDelete(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "HollowDrivers.lnk"));

            string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string installDir = Path.Combine(local, @"Programs\HollowDrivers");
            string dataDir = Path.Combine(local, "HollowDrivers");
            bool official = string.Equals(Path.GetFullPath(dir).TrimEnd('\\'), installDir, StringComparison.OrdinalIgnoreCase);
            if (official) File.WriteAllText(Path.Combine(installDir, ".uninstall-pending"), "pending");
            string script = @"$ErrorActionPreference='Stop'
$install=Join-Path $env:LOCALAPPDATA 'Programs\HollowDrivers'
$data=Join-Path $env:LOCALAPPDATA 'HollowDrivers'
Wait-Process -Id __PID__ -ErrorAction SilentlyContinue
$lease=[IO.File]::Open((Join-Path $data 'session.lock'),'OpenOrCreate','ReadWrite','None')
try {
 if (__REMOVE__) {
  if ((Get-Item -LiteralPath $install -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {throw 'Pasta redirecionada'}
  Remove-Item -LiteralPath $install -Recurse -Force
 }
} finally {$lease.Dispose()}
if (__WIPE__) {
 if ((Get-Item -LiteralPath $data -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {throw 'Pasta redirecionada'}
 Remove-Item -LiteralPath $data -Recurse -Force
}
";
            script = script.Replace("__PID__", Process.GetCurrentProcess().Id.ToString())
                .Replace("__REMOVE__", official ? "$true" : "$false").Replace("__WIPE__", wipe ? "$true" : "$false");
            var psi = new ProcessStartInfo("powershell.exe", "-NoProfile -WindowStyle Hidden -EncodedCommand " + Convert.ToBase64String(System.Text.Encoding.Unicode.GetBytes(script)));
            psi.CreateNoWindow = true;
            psi.UseShellExecute = false;
            psi.WorkingDirectory = Path.GetTempPath();
            Process.Start(psi);
            MessageBox.Show("Atalhos removidos. A limpeza dos arquivos ocorrerá ao fechar esta mensagem.", "HollowDrivers", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return 0;
            }
        }

        static void TryDelete(string f)
        {
            try { if (File.Exists(f)) File.Delete(f); } catch { }
        }

    }
}
