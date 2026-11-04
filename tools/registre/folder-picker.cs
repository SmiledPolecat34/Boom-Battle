using System;
using System.IO;
using System.Text;
using System.Windows.Forms;
using System.Drawing;

internal static class FolderPicker
{
    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length != 1) return 2;
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        using (var owner = new Form())
        using (var picker = new FolderBrowserDialog())
        {
            owner.Text = "Choisir un dossier de projet";
            owner.TopMost = true;
            owner.ShowInTaskbar = false;
            owner.StartPosition = FormStartPosition.CenterScreen;
            owner.Size = new Size(1, 1);
            owner.Opacity = 0;
            picker.Description = "Choisir un dossier de projet";
            picker.ShowNewFolderButton = false;
            owner.Show();
            owner.Activate();
            var chosen = picker.ShowDialog(owner) == DialogResult.OK ? picker.SelectedPath : "";
            File.WriteAllText(args[0], chosen, new UTF8Encoding(false));
        }
        return 0;
    }
}
