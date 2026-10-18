using System;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Org.BouncyCastle.Crypto.Parameters;
using Org.BouncyCastle.Crypto.Signers;
using Org.BouncyCastle.Security;

namespace Fly.LicenseIssuer
{
    internal sealed class IssuedLicense
    {
        public string Token;
        public string Machine;
        public DateTime ExpiresUtc;
        public bool Permanent;
        public int Days;
    }

    internal sealed class LicenseIssuer
    {
        private readonly Ed25519PrivateKeyParameters key;
        private readonly Ed25519PublicKeyParameters publicKey;
        public readonly string PublicKey;

        public LicenseIssuer(byte[] privateDer, string expectedPublic)
        {
            key = PrivateKeyFactory.CreateKey(privateDer) as Ed25519PrivateKeyParameters;
            if (key == null) throw new InvalidOperationException("授权签名身份格式错误。");
            publicKey = key.GeneratePublicKey();
            PublicKey = Encode(publicKey.GetEncoded());
            if (!String.Equals(PublicKey, expectedPublic.Trim(), StringComparison.Ordinal))
                throw new InvalidOperationException("授权签名身份与 Fly 公钥不一致，请恢复原始文件。");
        }

        public static LicenseIssuer FromEmbeddedIdentity()
        {
            byte[] pem = ResourceLoader.Read("Fly.License.Key");
            byte[] der = null;
            try
            {
                string text = Encoding.ASCII.GetString(pem);
                der = Convert.FromBase64String(Regex.Replace(text, @"-----[^-]+-----|\s", ""));
                string expected = Encoding.ASCII.GetString(ResourceLoader.Read("Fly.License.Public"));
                return new LicenseIssuer(der, expected);
            }
            finally { Array.Clear(pem, 0, pem.Length); if (der != null) Array.Clear(der, 0, der.Length); }
        }

        public static string NormalizeMachine(string value)
        {
            return Regex.Replace(value ?? "", @"\s", "").ToUpperInvariant();
        }

        public IssuedLicense Issue(string input, int days, bool permanent, DateTime now)
        {
            string machine = NormalizeMachine(input);
            if (!Regex.IsMatch(machine, @"\A[0-9A-F]{64}\z"))
                throw new ArgumentException("请输入完整的 64 位机器码，仅包含 0–9 和 A–F。");
            if (!permanent && (days < 1 || days > 36500))
                throw new ArgumentException("激活天数应为 1–36500 的整数。");
            if (now.Kind != DateTimeKind.Utc) throw new ArgumentException("签发时间必须使用 UTC。");

            DateTime expiry = permanent
                ? new DateTime(9999, 12, 31, 23, 59, 59, DateTimeKind.Utc)
                : now.AddDays(days);
            byte[] nonce = new byte[16];
            using (RandomNumberGenerator random = RandomNumberGenerator.Create()) random.GetBytes(nonce);
            string nonceHex = BitConverter.ToString(nonce).Replace("-", "").ToLowerInvariant();
            string payload = "{\"expiresAt\":\"" + Timestamp(expiry) +
                "\",\"issuedAt\":\"" + Timestamp(now) +
                "\",\"licenseVersion\":1,\"machineCode\":\"" + machine +
                "\",\"nonce\":\"" + nonceHex + "\"}";
            byte[] data = Encoding.UTF8.GetBytes(payload);
            Ed25519Signer signer = new Ed25519Signer();
            signer.Init(true, key);
            signer.BlockUpdate(data, 0, data.Length);
            byte[] signature = signer.GenerateSignature();
            Ed25519Signer verifier = new Ed25519Signer();
            verifier.Init(false, publicKey);
            verifier.BlockUpdate(data, 0, data.Length);
            if (!verifier.VerifySignature(signature))
                throw new InvalidOperationException("授权码校验失败，请重新生成。");
            return new IssuedLicense {
                Token = Encode(data) + "." + Encode(signature), Machine = machine,
                ExpiresUtc = expiry, Permanent = permanent, Days = permanent ? 0 : days
            };
        }

        public static string Timestamp(DateTime value)
        {
            return value.ToString("yyyy-MM-dd'T'HH:mm:ss.ffffff'Z'", CultureInfo.InvariantCulture);
        }

        public static string Encode(byte[] value)
        {
            return Convert.ToBase64String(value).TrimEnd('=').Replace('+', '-').Replace('/', '_');
        }
    }
}
