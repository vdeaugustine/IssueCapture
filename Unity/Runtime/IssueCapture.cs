using System;
using System.Runtime.CompilerServices;
using System.Threading;
using UnityEngine;

namespace VinWare.IssueCapture
{
    /// <summary>Development-build iOS host. All lifecycle methods run on Unity's main thread; reporters may record from workers.</summary>
    public static class IssueCapture
    {
        private static string session;
        private static int mainThread = 0;
        private static CaptureRunner runner;

        /// <summary>True only after explicit initialization in a development iOS player. Editor and production are disabled.</summary>
        public static bool IsEnabled => session != null;

        /// <summary>Whether native reporting is open or awaiting a frame. Poll on the main thread to gate game input if needed.</summary>
        public static bool IsPresenting
        {
            get { if (!IsEnabled) return false; RequireMainThread(); return NativeTransport.IsPresenting; }
        }

        /// <summary>Installs once after Unity's window is visible; false means disabled or not ready. Retry later if needed.</summary>
        public static bool Initialize(string projectID, string sourceRevision = null,
            int eventLimit = 50, int eventByteLimit = 262144)
        {
#if UNITY_IOS && !UNITY_EDITOR && DEVELOPMENT_BUILD
            if (IsEnabled) { RequireMainThread(); return true; }
            NativeTransport.RequireIdentifier(projectID, nameof(projectID));
            mainThread = Thread.CurrentThread.ManagedThreadId;
            string candidate = Guid.NewGuid().ToString();
            if (!NativeTransport.Initialize(new Command {
                operation = "initialize", session = candidate, projectID = projectID,
                sourceRevision = sourceRevision, eventLimit = eventLimit, eventByteLimit = eventByteLimit
            })) return false;
            session = candidate;
            var host = new GameObject("IssueCapture (development)");
            UnityEngine.Object.DontDestroyOnLoad(host);
            runner = host.AddComponent<CaptureRunner>();
            return true;
#else
            return false;
#endif
        }

        /// <summary>Registers an explicit instance. Parent must be from this session and still registered; IDs/names must be static.</summary>
        public static IssueScreen RegisterScreen(string stableID, string name, string typeName,
            IssueScreen parent = null, bool active = true,
            [CallerFilePath] string file = "", [CallerLineNumber] int line = 0)
        {
            if (!IsEnabled) return new IssueScreen(null, null);
            RequireMainThread();
            NativeTransport.RequireIdentifier(stableID, nameof(stableID));
            NativeTransport.RequireIdentifier(name, nameof(name));
            NativeTransport.RequireIdentifier(typeName, nameof(typeName));
            if (parent != null && (parent.Session != session || parent.IsDisposed))
                throw new ArgumentException("Parent must be a live surface in this session.", nameof(parent));
            var context = new ScreenContext {
                id = Guid.NewGuid().ToString(), parentID = parent?.Context.id ?? "", stableID = stableID,
                name = name, typeName = typeName, file = NativeTransport.SourceFile(file), line = Math.Max(0, line)
            };
            NativeTransport.Send(new Command { operation = "register", session = session, screen = context, active = active });
            return new IssueScreen(session, context);
        }

        /// <summary>Freezes context now, captures the next complete Unity frame, then opens the native editor.</summary>
        public static void Capture()
        {
            if (!IsEnabled) return;
            RequireMainThread();
            if (NativeTransport.BeginCapture()) runner.CaptureFrame();
        }

        /// <summary>Opens native saved reports with edit and text/PDF/ZIP export actions.</summary>
        public static void OpenInbox() => Send("inbox");

        /// <summary>Opens native screen and event coverage diagnostics.</summary>
        public static void OpenDiagnostics() => Send("diagnostics");

        /// <summary>Removes native UI and recording. Old reporters cannot write to a subsequent session.</summary>
        public static void Shutdown()
        {
            if (!IsEnabled) return;
            Send("shutdown");
            session = null;
            if (runner != null) UnityEngine.Object.Destroy(runner.gameObject);
            runner = null;
        }

        internal static void RunnerDestroyed(CaptureRunner destroyed)
        {
            if (runner == destroyed) Shutdown();
        }

        internal static void CancelCapture() => Send("cancel");

        private static void Send(string operation)
        {
            if (!IsEnabled) return;
            RequireMainThread();
            NativeTransport.Send(new Command { operation = operation, session = session });
        }

        internal static void RequireMainThread()
        {
            if (Thread.CurrentThread.ManagedThreadId != mainThread)
                throw new InvalidOperationException("IssueCapture lifecycle operations require the Unity main thread.");
        }
    }
}
