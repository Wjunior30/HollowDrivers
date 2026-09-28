using System;
using System.IO;
using System.Management;
using System.Threading;
namespace DG {
    public static class Maintenance {
        public static FileStream Acquire(string target) {
            string data = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HollowDrivers");
            Directory.CreateDirectory(data);
            FileStream lease = null;
            for (int i = 0; i < 20; i++) {
                try { lease = new FileStream(Path.Combine(data, "session.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None); break; }
                catch (IOException) { Thread.Sleep(250); }
            }
            if (lease == null) throw new IOException("Feche o HollowDrivers e o vigia perto do relógio. Aguarde backups e restaurações terminarem antes de continuar.");
            try {
                // Old versions lack the lease. Do not terminate them or unrelated checkouts.
                using (var search = new ManagementObjectSearcher("SELECT CommandLine FROM Win32_Process WHERE Name='powershell.exe'")) {
                    foreach (ManagementObject process in search.Get()) {
                        string command = Convert.ToString(process["CommandLine"]);
                        string script = Path.Combine(target, "HollowDrivers.ps1");
                        if (command.IndexOf(script, StringComparison.OrdinalIgnoreCase) >= 0)
                            throw new IOException("Uma versão anterior está aberta. Feche o aplicativo e o vigia antes de continuar.");
                    }
                }
                return lease;
            } catch { lease.Dispose(); throw; }
        }
    }
}
