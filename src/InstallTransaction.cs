using System;
using System.IO;
namespace DG {
    // Whole-directory swaps prevent partially mixed application versions.
    public static class InstallTransaction {
        public static void Recover(string target) {
            string backup = target + ".rollback";
            if (!Directory.Exists(backup)) return;
            Check(target); Check(backup);
            if (Directory.Exists(target)) Directory.Move(target, target + ".failed-" + Guid.NewGuid().ToString("N"));
            Directory.Move(backup, target);
        }
        static void Check(string path) {
            if (Directory.Exists(path) && (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
                throw new IOException("Pasta de instalação redirecionada. Operação cancelada.");
        }
        public static void Replace(string stage, string target, Action afterSwap) {
            if (Path.GetDirectoryName(Path.GetFullPath(stage)) != Path.GetDirectoryName(Path.GetFullPath(target)))
                throw new IOException("A preparação deve estar na mesma pasta do destino.");
            Check(stage); Check(target); Recover(target);
            string backup = target + ".rollback";
            bool hadPrevious = Directory.Exists(target);
            if (hadPrevious) Directory.Move(target, backup);
            try {
                Directory.Move(stage, target);
                if (afterSwap != null) afterSwap();
                if (hadPrevious) Directory.Move(backup, target + ".previous-" + Guid.NewGuid().ToString("N"));
            } catch {
                if (hadPrevious) Recover(target);
                else if (Directory.Exists(target)) Directory.Move(target, target + ".failed-" + Guid.NewGuid().ToString("N"));
                throw;
            }
        }
    }
}
