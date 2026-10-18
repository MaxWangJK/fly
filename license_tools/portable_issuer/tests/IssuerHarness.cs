using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.CompilerServices;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Org.BouncyCastle.Crypto.Parameters;
using Org.BouncyCastle.Security;
using Org.BouncyCastle.Pkcs;

namespace Fly.LicenseIssuer
{
    internal static class IssuerHarness
    {
        private static int assertions;
        private static void Check(bool condition, string name)
        {
            if (!condition) throw new Exception("Failed: " + name);
            assertions++;
        }
        private static void Reject(Action action, string name)
        {
            bool rejected = false;
            try { action(); } catch (ArgumentException) { rejected = true; }
            Check(rejected, name);
        }
        private static T Find<T>(Form form, string name) where T : Control
        {
            return (T)form.Controls.Find(name, true)[0];
        }
        [STAThread]
        private static int Main(string[] args)
        {
            ResourceLoader.Register();
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            try { return Run(args); }
            catch (Exception e) { Console.Error.WriteLine(e.GetType().Name + ": " + e.Message); return 1; }
        }
        [MethodImpl(MethodImplOptions.NoInlining)]
        private static int Run(string[] args)
        {
            LicenseIssuer original = LicenseIssuer.FromEmbeddedIdentity();
            Check(original.PublicKey.Length == 43, "original issuer identity matches embedded public key");
            Ed25519PrivateKeyParameters ephemeral = new Ed25519PrivateKeyParameters(new SecureRandom());
            string publicKey = LicenseIssuer.Encode(ephemeral.GeneratePublicKey().GetEncoded());
            byte[] testDer = PrivateKeyInfoFactory.CreatePrivateKeyInfo(ephemeral).GetEncoded();
            LicenseIssuer issuer = new LicenseIssuer(testDer, publicKey);
            bool mismatch = false;
            try { new LicenseIssuer(testDer, LicenseIssuer.Encode(new byte[32])); }
            catch (InvalidOperationException) { mismatch = true; }
            Check(mismatch, "mismatched identity refused");
            DateTime now = new DateTime(2026, 10, 17, 12, 0, 0, DateTimeKind.Utc);
            const string rawMachine = "fly-portable-issuer-isolated-fixture-v1";
            string machine;
            using (SHA256 hash = SHA256.Create()) machine = BitConverter.ToString(hash.ComputeHash(Encoding.UTF8.GetBytes("fly:v1:" + rawMachine))).Replace("-", "");
            IssuedLicense timed = issuer.Issue(machine, 30, false, now);
            IssuedLicense permanent = issuer.Issue(machine, 0, true, now);
            Check(timed.ExpiresUtc == now.AddDays(30), "exact day duration");
            Check(permanent.ExpiresUtc.Year == 9999 && permanent.Permanent, "permanent legacy contract");
            Check(issuer.Issue(" \r\n" + machine.ToLowerInvariant() + "\t", 1, false, now).Machine == machine, "paste normalization");
            Check(issuer.Issue(machine, 36500, false, now).ExpiresUtc == now.AddDays(36500), "maximum duration");
            Check(issuer.Issue(machine, 30, false, now).Token != timed.Token, "fresh cryptographic nonce");
            foreach (int duration in new int[] { -1, 0, 36501 })
                Reject(delegate { issuer.Issue(machine, duration, false, now); }, "duration rejected");
            foreach (string invalid in new string[] { "", new string('A', 63), new string('A', 65), new string('G', 64), new string('A', 63) + "!" })
                Reject(delegate { issuer.Issue(invalid, 30, false, now); }, "invalid machine rejected");
            Reject(delegate { issuer.Issue(machine, 30, false, DateTime.SpecifyKind(now, DateTimeKind.Unspecified)); }, "non UTC refused");

            string clipboard = null;
            using (IssuerForm form = new IssuerForm(issuer, delegate(string value) { clipboard = value; }))
            {
                form.ShowInTaskbar = false; form.Opacity = 0; form.Show(); Application.DoEvents();
                TextBox input = Find<TextBox>(form, "machine");
                TextBox token = Find<TextBox>(form, "token");
                Button generate = Find<Button>(form, "generate");
                Button copy = Find<Button>(form, "copy");
                NumericUpDown days = Find<NumericUpDown>(form, "days");
                generate.PerformClick(); Check(!copy.Enabled, "invalid input cannot generate or copy");
                input.Text = machine; generate.PerformClick();
                Check(copy.Enabled && token.Text.Contains("."), "valid UI issue");
                copy.PerformClick(); Check(clipboard == token.Text, "copy exact whole token without system clipboard changes");
                days.Value = 31; Check(!copy.Enabled, "duration change clears stale token");
                generate.PerformClick(); Check(copy.Enabled, "new duration can issue");
                Find<Button>(form, "permanent").PerformClick();
                Check(!days.Enabled && !copy.Enabled, "permanent selection clears old result and disables days");
                generate.PerformClick(); Check(copy.Enabled, "permanent UI issue");
                Dictionary<string, object> decoded = Decode(token.Text);
                Check(((string)decoded["expiresAt"]).StartsWith("9999-12-31"), "permanent UI payload");
                Find<Button>(form, "timed").PerformClick(); Check(days.Enabled && !copy.Enabled, "return to days mode");
                input.Text = machine; generate.PerformClick(); input.Text = new string('B', 64);
                Check(!copy.Enabled, "machine edit clears stale token");
                input.Text = "INVALID"; generate.PerformClick(); Check(!copy.Enabled, "invalid replacement cannot reuse old result");
                form.Close();
            }

            Dictionary<string, object> fixture = new Dictionary<string, object> {
                { "source", "C# portable issuer with ephemeral TEST key; never the production issuer" },
                { "publicKey", publicKey }, { "rawMachine", rawMachine },
                { "nowUtc", LicenseIssuer.Timestamp(now) }, { "timed", timed.Token },
                { "permanent", permanent.Token },
                { "expired", issuer.Issue(machine, 30, false, now.AddDays(-40)).Token },
                { "future", issuer.Issue(machine, 30, false, now.AddDays(1)).Token },
                { "wrongMachine", issuer.Issue(new string('A', 64), 30, false, now).Token }
            };
            File.WriteAllText(args[0], new JavaScriptSerializer().Serialize(fixture), new UTF8Encoding(false));
            Console.WriteLine("PASS: " + assertions + " core and real WinForms interaction assertions; ephemeral cross-language fixtures written.");
            return 0;
        }
        private static Dictionary<string, object> Decode(string token)
        {
            string value = token.Split('.')[0].Replace('-', '+').Replace('_', '/');
            value = value.PadRight((value.Length + 3) / 4 * 4, '=');
            return new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(Encoding.UTF8.GetString(Convert.FromBase64String(value)));
        }
    }
}
