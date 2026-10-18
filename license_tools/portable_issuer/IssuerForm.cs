using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace Fly.LicenseIssuer
{
    internal static class Palette
    {
        public static readonly Color Ink = Color.FromArgb(28, 42, 61);
        public static readonly Color Muted = Color.FromArgb(113, 127, 145);
        public static readonly Color Accent = Color.FromArgb(20, 109, 121);
        public static readonly Color Soft = Color.FromArgb(233, 246, 246);
        public static readonly Color Line = Color.FromArgb(223, 231, 239);
        public static readonly Color Error = Color.FromArgb(190, 61, 66);
        public static readonly Color Canvas = Color.FromArgb(244, 247, 250);
        public static Font Font(float size, FontStyle style = FontStyle.Regular)
        {
            return new Font("Microsoft YaHei UI", size, style, GraphicsUnit.Point);
        }
        public static GraphicsPath Rounded(Rectangle bounds, int radius)
        {
            GraphicsPath path = new GraphicsPath();
            int d = Math.Min(radius * 2, Math.Min(bounds.Width, bounds.Height));
            path.AddArc(bounds.X, bounds.Y, d, d, 180, 90);
            path.AddArc(bounds.Right - d, bounds.Y, d, d, 270, 90);
            path.AddArc(bounds.Right - d, bounds.Bottom - d, d, d, 0, 90);
            path.AddArc(bounds.X, bounds.Bottom - d, d, d, 90, 90);
            path.CloseFigure();
            return path;
        }
    }

    internal sealed class Card : Panel
    {
        public Color Fill = Color.White;
        public Color Border = Palette.Line;
        public int Radius = 16;
        public Card()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                ControlStyles.OptimizedDoubleBuffer | ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            Rectangle area = new Rectangle(0, 0, Width - 1, Height - 1);
            using (GraphicsPath path = Palette.Rounded(area, Radius))
            using (SolidBrush fill = new SolidBrush(Fill))
            using (Pen border = new Pen(Border))
            {
                e.Graphics.FillPath(fill, path);
                e.Graphics.DrawPath(border, path);
            }
        }
    }

    internal sealed class ActionButton : Button
    {
        public Color Fill = Color.White;
        public Color Edge = Palette.Line;
        public Color Ink = Palette.Ink;
        private bool hovered;
        public ActionButton()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                ControlStyles.OptimizedDoubleBuffer | ControlStyles.SupportsTransparentBackColor, true);
            Font = Palette.Font(10);
            BackColor = Color.Transparent;
            FlatStyle = FlatStyle.Flat;
            FlatAppearance.BorderSize = 0;
            Cursor = Cursors.Hand;
            UseVisualStyleBackColor = false;
        }
        protected override void OnMouseEnter(EventArgs e) { hovered = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hovered = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }
        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            Color fill = Enabled ? Fill : Color.FromArgb(239, 242, 246);
            if (hovered && Enabled) fill = ControlPaint.Dark(fill, 0.035f);
            using (GraphicsPath path = Palette.Rounded(new Rectangle(1, 1, Width - 3, Height - 3), 10))
            using (SolidBrush brush = new SolidBrush(fill))
            using (Pen border = new Pen(Enabled ? Edge : Palette.Line))
            {
                e.Graphics.FillPath(brush, path);
                e.Graphics.DrawPath(border, path);
            }
            TextRenderer.DrawText(e.Graphics, Text, Font, ClientRectangle,
                Enabled ? Ink : Palette.Muted,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
            if (Focused && ShowFocusCues)
                ControlPaint.DrawFocusRectangle(e.Graphics, Rectangle.Inflate(ClientRectangle, -6, -6));
        }
    }

    internal sealed class IssuerForm : Form
    {
        private readonly LicenseIssuer issuer;
        private readonly Action<string> copyAction;
        private readonly TextBox machine;
        private readonly NumericUpDown days;
        private readonly TextBox output;
        private readonly ActionButton timed;
        private readonly ActionButton permanent;
        private readonly ActionButton copy;
        private readonly Label machineHint;
        private readonly Label counter;
        private readonly Label expiryHint;
        private readonly Label resultHint;
        private readonly Label footer;
        private readonly Timer toast;
        private bool isPermanent;
        private string currentToken;

        public IssuerForm(LicenseIssuer engine, Action<string> clipboard = null)
        {
            issuer = engine;
            copyAction = clipboard ?? new Action<string>(Clipboard.SetText);
            AutoScaleDimensions = new SizeF(96, 96);
            AutoScaleMode = AutoScaleMode.Dpi;
            Text = "Fly 授权工具";
            Font = Palette.Font(10);
            ForeColor = Palette.Ink;
            BackColor = Palette.Canvas;
            ClientSize = new Size(720, 680);
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            DoubleBuffered = true;
            using (System.IO.Stream icon = System.Reflection.Assembly.GetExecutingAssembly().GetManifestResourceStream("Fly.License.Icon"))
                if (icon != null) Icon = new Icon(icon);

            Card mark = Box(this, 28, 27, 44, 44);
            mark.Fill = Palette.Accent; mark.Border = Palette.Accent; mark.Radius = 12;
            Label letter = Label(mark, "F", 0, 2, 44, 38, 22, FontStyle.Bold);
            letter.TextAlign = ContentAlignment.MiddleCenter; letter.ForeColor = Color.White;
            Label(this, "Fly 授权工具", 86, 24, 340, 34, 19, FontStyle.Bold);
            Label(this, "为一台设备，签发一份专属授权。", 87, 64, 480, 24, 10).ForeColor = Palette.Muted;
            Card badge = Box(this, 594, 30, 98, 30);
            badge.Fill = Palette.Soft; badge.Border = Palette.Soft; badge.Radius = 12;
            Label status = Label(badge, "●  离线签发", 0, 1, 98, 28, 9);
            status.TextAlign = ContentAlignment.MiddleCenter; status.ForeColor = Palette.Accent;

            Card input = Box(this, 28, 108, 664, 266);
            Label(input, "机器码", 24, 21, 180, 24, 10, FontStyle.Bold);
            Card machineField = Box(input, 24, 54, 616, 48); machineField.Radius = 10;
            machineField.Fill = Color.FromArgb(249, 251, 253);
            machine = new TextBox {
                Name = "machine", AccessibleName = "机器码", BorderStyle = BorderStyle.None,
                Location = new Point(14, 15), Size = new Size(504, 22), MaxLength = 256,
                Font = new Font("Consolas", 9.5f), CharacterCasing = CharacterCasing.Upper,
                BackColor = machineField.Fill, ForeColor = Palette.Ink, TabIndex = 0
            };
            machineField.Controls.Add(machine);
            ActionButton paste = Button(machineField, "粘贴", "paste", 530, 7, 76, 34);
            paste.TabIndex = 1;
            paste.Fill = Color.White;
            paste.Click += delegate {
                try {
                    if (Clipboard.ContainsText()) machine.Text = LicenseIssuer.NormalizeMachine(Clipboard.GetText());
                    machine.Focus(); machine.SelectionStart = machine.TextLength;
                }
                catch (ExternalException) { Notice("剪贴板暂不可用，请使用 Ctrl+V 粘贴。", true); }
            };
            machineHint = Label(input, "粘贴 Fly 中显示的完整机器码", 24, 109, 510, 22, 9);
            machineHint.ForeColor = Palette.Muted;
            counter = Label(input, "0 / 64", 550, 109, 90, 22, 9);
            counter.TextAlign = ContentAlignment.MiddleRight; counter.ForeColor = Palette.Muted;
            Label(input, "授权期限", 24, 148, 180, 24, 10, FontStyle.Bold);
            timed = Button(input, "按天授权", "timed", 24, 181, 128, 40);
            permanent = Button(input, "永久授权", "permanent", 162, 181, 128, 40);
            timed.TabIndex = 2; permanent.TabIndex = 3;
            Card dayField = Box(input, 310, 181, 330, 40); dayField.Radius = 10;
            days = new NumericUpDown {
                Name = "days", AccessibleName = "激活天数", Minimum = 1, Maximum = 36500,
                Value = 30, Location = new Point(14, 9), Size = new Size(95, 24),
                Font = Palette.Font(10), BorderStyle = BorderStyle.None, TabIndex = 4
            };
            dayField.Controls.Add(days);
            Label(dayField, "天", 121, 8, 30, 25, 10);
            Label(dayField, "1–36500 天", 205, 10, 110, 23, 9).ForeColor = Palette.Muted;
            expiryHint = Label(input, "", 24, 229, 616, 24, 9);
            expiryHint.ForeColor = Palette.Muted;

            ActionButton generate = Button(this, "生成授权码", "generate", 28, 388, 664, 48);
            generate.Fill = Palette.Accent; generate.Edge = Palette.Accent; generate.Ink = Color.White;
            generate.Font = Palette.Font(11, FontStyle.Bold); generate.TabIndex = 5;
            generate.Click += delegate { Generate(); };
            AcceptButton = generate;

            Card result = Box(this, 28, 454, 664, 172);
            Label(result, "授权码", 24, 18, 130, 27, 10, FontStyle.Bold);
            resultHint = Label(result, "等待生成", 154, 21, 340, 24, 9);
            resultHint.ForeColor = Palette.Muted;
            copy = Button(result, "复制授权码", "copy", 532, 13, 108, 36);
            copy.TabIndex = 6; copy.Enabled = false;
            Card tokenField = Box(result, 24, 61, 616, 98);
            tokenField.Fill = Color.FromArgb(249, 251, 253); tokenField.Radius = 10;
            output = new TextBox {
                Name = "token", AccessibleName = "生成的授权码", Multiline = true, ReadOnly = true,
                Location = new Point(13, 12), Size = new Size(588, 75), BorderStyle = BorderStyle.None,
                BackColor = tokenField.Fill, ForeColor = Palette.Muted, Font = new Font("Consolas", 10),
                ScrollBars = ScrollBars.Vertical, Text = "生成后的授权码将显示在这里。", TabIndex = 7
            };
            tokenField.Controls.Add(output);
            output.KeyDown += delegate(object sender, KeyEventArgs e) {
                if (e.Control && e.KeyCode == Keys.A) { output.SelectAll(); e.SuppressKeyPress = true; }
            };
            copy.Click += delegate {
                if (String.IsNullOrEmpty(currentToken)) return;
                try { copyAction(currentToken); Notice("✓  已复制，可粘贴到对应设备的 Fly 中激活。", false); }
                catch (ExternalException) { Notice("剪贴板暂不可用，请选中授权码后按 Ctrl+C。", true); }
            };
            footer = Label(this, "仅供内部签发 · 请妥善保管此工具", 28, 644, 664, 24, 9);
            footer.ForeColor = Palette.Muted;
            toast = new Timer { Interval = 3500 };
            toast.Tick += delegate { toast.Stop(); footer.ForeColor = Palette.Muted; footer.Text = "仅供内部签发 · 请妥善保管此工具"; };
            timed.Click += delegate { SetMode(false); };
            permanent.Click += delegate { SetMode(true); };
            machine.TextChanged += delegate {
                int count = LicenseIssuer.NormalizeMachine(machine.Text).Length;
                counter.Text = count.ToString(CultureInfo.InvariantCulture) + " / 64";
                machineHint.Text = "粘贴 Fly 中显示的完整机器码";
                machineHint.ForeColor = Palette.Muted;
                ClearResult();
            };
            days.ValueChanged += delegate { ClearResult(); UpdateExpiry(); };
            SetMode(false);
            Shown += delegate { machine.Focus(); };
        }

        private static Card Box(Control parent, int x, int y, int width, int height)
        {
            Card result = new Card { Bounds = new Rectangle(x, y, width, height) };
            parent.Controls.Add(result); return result;
        }
        private static Label Label(Control parent, string text, int x, int y, int width, int height,
            float size, FontStyle style = FontStyle.Regular)
        {
            Label result = new Label { Text = text, Bounds = new Rectangle(x, y, width, height),
                Font = Palette.Font(size, style), BackColor = Color.Transparent, ForeColor = Palette.Ink,
                TextAlign = ContentAlignment.MiddleLeft, AutoEllipsis = true };
            parent.Controls.Add(result); return result;
        }
        private static ActionButton Button(Control parent, string text, string name, int x, int y, int width, int height)
        {
            ActionButton result = new ActionButton { Text = text, Name = name, AccessibleName = text,
                Bounds = new Rectangle(x, y, width, height) };
            parent.Controls.Add(result); return result;
        }
        private void SetMode(bool value)
        {
            isPermanent = value;
            days.Enabled = !value;
            timed.Fill = value ? Color.White : Palette.Soft;
            timed.Edge = value ? Palette.Line : Palette.Accent;
            timed.Ink = value ? Palette.Ink : Palette.Accent;
            permanent.Fill = value ? Palette.Soft : Color.White;
            permanent.Edge = value ? Palette.Accent : Palette.Line;
            permanent.Ink = value ? Palette.Accent : Palette.Ink;
            timed.Invalidate(); permanent.Invalidate();
            ClearResult(); UpdateExpiry();
        }
        private void UpdateExpiry()
        {
            expiryHint.Text = isPermanent ? "永久有效，无到期限制。" :
                "从生成时开始计时，预计有效至 " + DateTime.Now.AddDays((double)days.Value).ToString("yyyy-MM-dd HH:mm") + "。";
        }
        private void ClearResult()
        {
            currentToken = null; copy.Enabled = false;
            output.Text = "生成后的授权码将显示在这里。"; output.ForeColor = Palette.Muted;
            resultHint.Text = "等待生成"; resultHint.ForeColor = Palette.Muted;
            if (toast != null) toast.Stop();
            if (footer != null) { footer.Text = "仅供内部签发 · 请妥善保管此工具"; footer.ForeColor = Palette.Muted; }
        }
        private void Generate()
        {
            ClearResult();
            try
            {
                IssuedLicense issued = issuer.Issue(machine.Text, (int)days.Value, isPermanent, DateTime.UtcNow);
                currentToken = issued.Token;
                output.ForeColor = Palette.Ink; output.Text = currentToken;
                output.SelectionStart = 0; output.SelectionLength = 0;
                copy.Enabled = true;
                resultHint.Text = issued.Permanent ? "✓  永久授权 · 签名已校验" :
                    "✓  " + issued.Days + " 天授权 · 签名已校验";
                resultHint.ForeColor = Palette.Accent;
                expiryHint.Text = issued.Permanent ? "永久有效，无到期限制。" :
                    "有效至 " + issued.ExpiresUtc.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss") + "（从生成时开始计时）";
                Notice("✓  授权码已生成，请复制给对应设备使用。", false);
            }
            catch (ArgumentException e)
            {
                machineHint.Text = e.Message; machineHint.ForeColor = Palette.Error;
                machine.Focus();
            }
            catch (Exception) { Notice("生成失败，请检查电脑时间，或恢复原始内部工具后重试。", true); }
        }
        private void Notice(string message, bool error)
        {
            footer.Text = message; footer.ForeColor = error ? Palette.Error : Palette.Accent;
            toast.Stop(); toast.Start();
        }
        internal void PreparePreview()
        {
            machine.Text = "7AC431E5C8D290B67311AF09E6CB4532D87FA102B9EC620445DE8721AB3F909C";
            Generate();
        }
        protected override void Dispose(bool disposing)
        {
            if (disposing && toast != null) toast.Dispose();
            base.Dispose(disposing);
        }
    }
}
