using System;
using System.Drawing;
using System.IO;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace Fly.LicenseIssuer
{
    internal static class Program
    {
        [DllImport("user32.dll")] private static extern bool SetProcessDpiAwarenessContext(IntPtr context);
        [DllImport("user32.dll")] private static extern bool SetProcessDPIAware();

        [STAThread]
        private static int Main(string[] args)
        {
            ResourceLoader.Register();
            try { SetProcessDpiAwarenessContext(new IntPtr(-4)); }
            catch (EntryPointNotFoundException) { SetProcessDPIAware(); }
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            try { return Run(args); }
            catch (Exception)
            {
                if (args.Length > 0) return 1;
                MessageBox.Show("授权工具启动失败。请使用完整的原始内部工具，或从原签名文件重新构建。", "Fly 授权工具",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
        }

        [MethodImpl(MethodImplOptions.NoInlining)]
        private static int Run(string[] args)
        {
            LicenseIssuer issuer = LicenseIssuer.FromEmbeddedIdentity();
            using (IssuerForm form = new IssuerForm(issuer))
            {
                if (args.Length == 2 && args[0] == "--preview")
                {
                    form.ShowInTaskbar = false;
                    form.Opacity = 0;
                    form.Show();
                    form.PreparePreview();
                    Application.DoEvents();
                    using (Bitmap image = new Bitmap(form.Width, form.Height))
                    {
                        form.DrawToBitmap(image, new Rectangle(Point.Empty, form.Size));
                        image.Save(Path.GetFullPath(args[1]), System.Drawing.Imaging.ImageFormat.Png);
                    }
                    form.Close();
                    return 0;
                }
                Application.Run(form);
            }
            return 0;
        }
    }
}
