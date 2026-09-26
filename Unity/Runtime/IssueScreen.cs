using System;

namespace VinWare.IssueCapture
{
    /// <summary>A registered scene, retained UI surface, or overlay. Dispose on destruction; toggle activity on routing.</summary>
    public sealed class IssueScreen : IDisposable
    {
        internal readonly ScreenContext Context;
        internal readonly string Session;
        private bool disposed;

        internal IssueScreen(string session, ScreenContext context)
        {
            Session = session;
            Context = context;
            Reporter = session == null ? IssueReporter.Disabled : new IssueReporter(session, context);
        }

        /// <summary>Origin-bound event sink that remains valid for late outcomes after this surface is destroyed.</summary>
        public IssueReporter Reporter { get; }

        /// <summary>Controls visibility candidacy, including descendants; does not enable/disable GameObjects.</summary>
        public void SetActive(bool active)
        {
            if (Session == null || disposed) return;
            IssueCapture.RequireMainThread();
            NativeTransport.Send(new Command { operation = "active", session = Session, screen = Context, active = active });
        }

        /// <summary>Unregisters this instance and makes its descendants inactive. Existing reporters keep their origin.</summary>
        public void Dispose()
        {
            if (Session == null || disposed) return;
            IssueCapture.RequireMainThread();
            disposed = true;
            NativeTransport.Send(new Command { operation = "dispose", session = Session, screen = Context });
        }

        internal bool IsDisposed => disposed;
    }
}
