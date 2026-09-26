using System.Runtime.CompilerServices;

namespace VinWare.IssueCapture
{
    /// <summary>Allowed operation outcomes; freeform metadata and error messages are deliberately excluded.</summary>
    public enum IssueOutcome { Success, Failure, Cancelled }

    /// <summary>Immutable origin scope. Retain for asynchronous completion, even after its screen is disposed.</summary>
    public sealed class IssueReporter
    {
        internal static readonly IssueReporter Disabled = new IssueReporter(null, null);
        private readonly string session;
        private readonly ScreenContext context;

        internal IssueReporter(string session, ScreenContext context)
        {
            this.session = session;
            this.context = context;
        }

        /// <summary>Records a static semantic action from the existing uGUI handler, never a field value.</summary>
        public void Action(string name, [CallerFilePath] string file = "", [CallerLineNumber] int line = 0)
            => Record("action", name, null, file, line);

        /// <summary>Records an explicit routing decision without inferring the current Unity scene.</summary>
        public void Navigation(string name, [CallerFilePath] string file = "", [CallerLineNumber] int line = 0)
            => Record("navigation", name, null, file, line);

        /// <summary>Records an allowlisted result using the original screen and capture session.</summary>
        public void Outcome(string name, IssueOutcome result,
            [CallerFilePath] string file = "", [CallerLineNumber] int line = 0)
            => Record("outcome", name, result.ToString().ToLowerInvariant(), file, line);

        private void Record(string category, string name, string result, string file, int line)
        {
            if (session == null) return;
            NativeTransport.RequireIdentifier(name, nameof(name));
            NativeTransport.Send(new Command {
                operation = "record", session = session, screen = context, category = category,
                name = name, result = result, file = NativeTransport.SourceFile(file), line = System.Math.Max(0, line)
            });
        }
    }
}
