using System;
using System.IO;
using System.IO.Compression;
using System.Reflection;

namespace Fly.LicenseIssuer
{
    internal static class ResourceLoader
    {
        public static void Register()
        {
            AppDomain.CurrentDomain.AssemblyResolve += delegate(object sender, ResolveEventArgs e) {
                if (new AssemblyName(e.Name).Name != "BouncyCastle.Cryptography") return null;
                using (MemoryStream compressed = new MemoryStream(Read("Fly.License.Crypto")))
                using (GZipStream inflater = new GZipStream(compressed, CompressionMode.Decompress))
                using (MemoryStream bytes = new MemoryStream())
                {
                    inflater.CopyTo(bytes);
                    return Assembly.Load(bytes.ToArray());
                }
            };
        }

        public static byte[] Read(string name)
        {
            using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(name))
            {
                if (stream == null) throw new InvalidOperationException("内部资源缺失，请重新构建授权工具。");
                using (MemoryStream bytes = new MemoryStream())
                {
                    stream.CopyTo(bytes);
                    return bytes.ToArray();
                }
            }
        }
    }
}
